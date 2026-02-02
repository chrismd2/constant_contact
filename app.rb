# frozen_string_literal: true

require 'sinatra'
require 'sinatra/json'
require 'faraday'
require 'json'
require 'dotenv/load'
require 'base64'
require 'uri'
require 'securerandom'
require 'fileutils'

# OAuth2 Client for Constant Contact
class ConstantContactOAuth2
  AUTH_URL = 'https://authz.constantcontact.com/oauth2/default/v1/authorize'.freeze
  TOKEN_URL = 'https://authz.constantcontact.com/oauth2/default/v1/token'.freeze

  def initialize(client_id, client_secret = nil, redirect_uri = nil, logger = nil)
    @client_id = client_id
    @client_secret = client_secret
    @redirect_uri = redirect_uri
    @logger = logger
    @conn = Faraday.new do |f|
      f.request :url_encoded
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  def authorization_url(state = nil, scopes = ['contact_data', 'offline_access'], redirect_uri = nil)
    redirect_uri ||= @redirect_uri
    params = {
      client_id: @client_id,
      redirect_uri: redirect_uri,
      response_type: 'code',
      scope: scopes.join(' '),
      access_type: 'offline'
    }
    params[:state] = state if state
    
    uri = URI(AUTH_URL)
    uri.query = URI.encode_www_form(params)
    uri.to_s
  end

  def exchange_code_for_token(authorization_code)
    @logger&.info "[OAuth2] Exchanging authorization code for token"
    
    unless @client_secret
      @logger&.error "[OAuth2] Client secret required for token exchange"
      return { success: false, error: { message: 'Client secret required for token exchange' }, status: 500 }
    end
    
    credentials = Base64.strict_encode64("#{@client_id}:#{@client_secret}")
    
    response = @conn.post(TOKEN_URL) do |req|
      req.headers['Authorization'] = "Basic #{credentials}"
      req.headers['Accept'] = 'application/json'
      req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
      req.body = {
        grant_type: 'authorization_code',
        code: authorization_code,
        redirect_uri: @redirect_uri
      }
    end
    
    log_oauth_response(response)
    handle_token_response(response)
  end

  def refresh_token(refresh_token_value)
    @logger&.info "[OAuth2] Refreshing access token"
    @logger&.info "[OAuth2] Refresh token present: #{refresh_token_value ? 'yes' : 'no'}"
    
    unless @client_secret
      @logger&.error "[OAuth2] Client secret required for token refresh"
      return { success: false, error: { message: 'Client secret required for token refresh' }, status: 500 }
    end
    
    credentials = Base64.strict_encode64("#{@client_id}:#{@client_secret}")
    
    # According to Constant Contact docs, refresh_token and grant_type should be in query params
    token_url_with_params = "#{TOKEN_URL}?refresh_token=#{URI.encode_www_form_component(refresh_token_value)}&grant_type=refresh_token"
    
    @logger&.info "[OAuth2] Refresh token URL: #{TOKEN_URL} (with query params)"
    
    response = @conn.post(token_url_with_params) do |req|
      req.headers['Authorization'] = "Basic #{credentials}"
      req.headers['Accept'] = 'application/json'
      req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
    end
    
    log_oauth_response(response)
    handle_token_response(response)
  end

  private

  def log_oauth_response(response)
    return unless @logger
    
    @logger.info "[OAuth2] Response Status: #{response.status}"
    @logger.info "[OAuth2] Response Headers: #{response.headers.inspect}"
    if response.body.is_a?(Hash)
      # Mask sensitive tokens in logs
      body = response.body.dup
      body['access_token'] = "[REDACTED]" if body['access_token']
      body['refresh_token'] = "[REDACTED]" if body['refresh_token']
      @logger.info "[OAuth2] Response Body: #{body.inspect}"
    else
      @logger.info "[OAuth2] Response Body: #{response.body.inspect}"
    end
  end

  def handle_token_response(response)
    case response.status
    when 200
      { success: true, data: response.body, status: response.status }
    when 400..499
      { success: false, error: response.body, status: response.status }
    when 500..599
      { success: false, error: { message: 'OAuth2 server error' }, status: response.status }
    else
      { success: false, error: { message: 'Unknown OAuth2 error' }, status: response.status }
    end
  end
end

# Token Storage - Persists OAuth2 tokens to disk
class TokenStorage
  TOKEN_FILE = '.tokens.json'.freeze

  def self.save(access_token, refresh_token, expires_at = nil)
    token_data = {
      access_token: access_token,
      refresh_token: refresh_token,
      expires_at: expires_at || (Time.now.to_i + 86400), # Default 24 hours
      updated_at: Time.now.to_i
    }
    
    File.write(TOKEN_FILE, JSON.pretty_generate(token_data))
    token_data
  end

  def self.load
    return nil unless File.exist?(TOKEN_FILE)
    
    begin
      data = JSON.parse(File.read(TOKEN_FILE))
      {
        access_token: data['access_token'],
        refresh_token: data['refresh_token'],
        expires_at: data['expires_at'],
        updated_at: data['updated_at']
      }
    rescue => e
      nil
    end
  end

  def self.update_access_token(access_token, expires_at = nil)
    tokens = load
    return nil unless tokens
    
    save(access_token, tokens[:refresh_token], expires_at)
  end

  def self.clear
    File.delete(TOKEN_FILE) if File.exist?(TOKEN_FILE)
  end
end

# Environment File Updater - Updates .env files with OAuth tokens
class EnvFileUpdater
  def self.update_tokens(access_token, refresh_token, logger = nil)
    env_file = '.env'
    logger&.info "[EnvFileUpdater] Updating tokens in #{env_file}"
    
    unless File.exist?(env_file)
      logger&.warn "[EnvFileUpdater] #{env_file} does not exist, creating it"
      File.write(env_file, "# Constant Contact API Configuration\n")
    end
    
    content = File.read(env_file)
    
    # Update or add CONSTANT_CONTACT_ACCESS_TOKEN
    if content =~ /^CONSTANT_CONTACT_ACCESS_TOKEN=/
      content.gsub!(/^CONSTANT_CONTACT_ACCESS_TOKEN=.*$/, "CONSTANT_CONTACT_ACCESS_TOKEN=#{access_token}")
    else
      content += "\nCONSTANT_CONTACT_ACCESS_TOKEN=#{access_token}\n"
    end
    
    # Update or add CONSTANT_CONTACT_REFRESH_TOKEN
    if content =~ /^CONSTANT_CONTACT_REFRESH_TOKEN=/
      content.gsub!(/^CONSTANT_CONTACT_REFRESH_TOKEN=.*$/, "CONSTANT_CONTACT_REFRESH_TOKEN=#{refresh_token}")
    else
      content += "\nCONSTANT_CONTACT_REFRESH_TOKEN=#{refresh_token}\n"
    end
    
    File.write(env_file, content)
    logger&.info "[EnvFileUpdater] Successfully updated #{env_file}"
    
    # Also update runtime environment variables
    ENV['CONSTANT_CONTACT_ACCESS_TOKEN'] = access_token
    ENV['CONSTANT_CONTACT_REFRESH_TOKEN'] = refresh_token
    
    env_file
  rescue => e
    logger&.error "[EnvFileUpdater] Error updating #{env_file}: #{e.message}"
    logger&.error "[EnvFileUpdater] #{e.backtrace.join("\n")}"
    nil
  end
end

# JWT Token Utilities
module JWTUtils
  def self.parse_jwt(token)
    # JWT tokens have 3 parts separated by dots
    parts = token.split('.')
    return nil unless parts.length == 3
    
    # Decode the payload (second part)
    begin
      payload = parts[1]
      # Add padding if needed
      payload += '=' * (4 - payload.length % 4) if payload.length % 4 != 0
      decoded = Base64.urlsafe_decode64(payload)
      JSON.parse(decoded)
    rescue => e
      nil
    end
  end

  def self.token_expired?(token)
    claims = parse_jwt(token)
    return true unless claims && claims['exp']
    
    expiration_time = claims['exp']
    current_time = Time.now.to_i
    current_time >= expiration_time
  end

  def self.token_expires_in(token)
    claims = parse_jwt(token)
    return nil unless claims && claims['exp']
    
    expiration_time = claims['exp']
    current_time = Time.now.to_i
    expiration_time - current_time
  end
end

# Constant Contact API Wrapper
class ConstantContactAPI
  BASE_URL = 'https://api.cc.email/v3'.freeze

  def initialize(access_token, logger = nil)
    @access_token = access_token
    @logger = logger
    @conn = Faraday.new(url: BASE_URL) do |f|
      f.request :json
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  def get_contacts(params = {})
    log_request('GET', 'contacts', params)
    response = @conn.get('contacts') do |req|
      req.headers['Authorization'] = "Bearer #{@access_token}"
      req.headers['Accept'] = 'application/json'
      req.params.merge!(params)
    end
    log_response(response)
    handle_response(response)
  end

  def get_contact(contact_id)
    log_request('GET', "contacts/#{contact_id}", {})
    response = @conn.get("contacts/#{contact_id}") do |req|
      req.headers['Authorization'] = "Bearer #{@access_token}"
      req.headers['Accept'] = 'application/json'
    end
    log_response(response)
    handle_response(response)
  end

  def create_contact(contact_data)
    log_request('POST', 'contacts', contact_data)
    response = @conn.post('contacts') do |req|
      req.headers['Authorization'] = "Bearer #{@access_token}"
      req.headers['Accept'] = 'application/json'
      req.body = contact_data
    end
    log_response(response)
    handle_response(response)
  end

  def update_contact(contact_id, contact_data)
    log_request('PUT', "contacts/#{contact_id}", contact_data)
    response = @conn.put("contacts/#{contact_id}") do |req|
      req.headers['Authorization'] = "Bearer #{@access_token}"
      req.headers['Accept'] = 'application/json'
      req.body = contact_data
    end
    log_response(response)
    handle_response(response)
  end

  def delete_contact(contact_id)
    log_request('DELETE', "contacts/#{contact_id}", {})
    response = @conn.delete("contacts/#{contact_id}") do |req|
      req.headers['Authorization'] = "Bearer #{@access_token}"
      req.headers['Accept'] = 'application/json'
    end
    log_response(response)
    handle_response(response)
  end

  private

  def log_request(method, endpoint, data)
    return unless @logger
    
    token_status = @access_token ? "present (#{@access_token[0..10]}...)" : "MISSING"
    @logger.info "[ConstantContactAPI] #{method} #{BASE_URL}/#{endpoint}"
    @logger.info "[ConstantContactAPI] Access token: #{token_status}"
    @logger.info "[ConstantContactAPI] Headers: Authorization=Bearer [REDACTED], Accept=application/json"
    @logger.info "[ConstantContactAPI] Params/Body: #{data.inspect}" unless data.empty?
  end

  def log_response(response)
    return unless @logger
    
    @logger.info "[ConstantContactAPI] Response Status: #{response.status}"
    @logger.info "[ConstantContactAPI] Response Headers: #{response.headers.inspect}"
    # Handle nil or empty response bodies (common for 204 No Content)
    if response.body.nil?
      @logger.info "[ConstantContactAPI] Response Body: nil"
    elsif response.body.is_a?(String) && response.body.empty?
      @logger.info "[ConstantContactAPI] Response Body: (empty string)"
    else
      @logger.info "[ConstantContactAPI] Response Body: #{response.body.inspect}"
    end
  end

  def handle_response(response)
    case response.status
    when 200..299
      # For 204 No Content, body is typically nil or empty
      data = (response.status == 204) ? nil : response.body
      { success: true, data: data, status: response.status }
    when 400..499
      # Handle case where error response body might not be valid JSON
      error_data = response.body
      if error_data.is_a?(Hash)
        # Already parsed JSON
        parsed_error = error_data
      elsif error_data.is_a?(String) && !error_data.empty?
        begin
          parsed_error = JSON.parse(error_data)
        rescue JSON::ParserError
          parsed_error = { message: error_data }
        end
      else
        parsed_error = { message: 'Client error' }
      end
      { success: false, error: parsed_error, status: response.status }
    when 500..599
      { success: false, error: { message: 'Constant Contact API server error' }, status: response.status }
    else
      { success: false, error: { message: 'Unknown error' }, status: response.status }
    end
  end
end

# Sinatra Application
class ConstantContactApp < Sinatra::Base
  configure do
    set :port, ENV.fetch('PORT', 4567).to_i
    set :bind, '0.0.0.0'
    enable :logging
    set :public_folder, File.join(File.dirname(__FILE__), 'public')
  end

  # Class variable to track if we've logged token status
  @@token_status_logged = false

  before do
    # Log token status on first request
    unless @@token_status_logged
      stored_tokens = TokenStorage.load
      if stored_tokens
        logger.info "[Startup] Found stored tokens (updated: #{Time.at(stored_tokens[:updated_at]).strftime('%Y-%m-%d %H:%M:%S')})"
        expires_at = stored_tokens[:expires_at] || 0
        if Time.now.to_i < expires_at
          logger.info "[Startup] Stored access token is valid (expires in #{expires_at - Time.now.to_i} seconds)"
        else
          logger.warn "[Startup] Stored access token is expired"
        end
      else
        logger.info "[Startup] No stored tokens found. Use /oauth/authorize to obtain tokens."
      end
      @@token_status_logged = true
    end
    
    # Skip OAuth endpoints, frontend pages, and static files from token validation
    if request.path.start_with?('/oauth/') || 
       request.path == '/' || 
       request.path == '/contacts/new' ||
       request.path.match?(%r{^/contacts/[^/]+/edit$}) ||
       request.path.start_with?('/js/') ||
       request.path.start_with?('/css/') ||
       request.path.start_with?('/health')
      return
    end
    
    # For /contacts, check if it's an HTML request (frontend) or JSON (API)
    if request.path == '/contacts'
      accept_header = request.env['HTTP_ACCEPT'].to_s.downcase
      query_string = request.env['QUERY_STRING'].to_s
      # If Accept header explicitly includes application/json or has query params, treat as API
      has_query_params = !query_string.nil? && !query_string.empty?
      wants_json = accept_header.include?('application/json') || has_query_params
      unless wants_json
        # HTML request - skip authentication
        return
      end
    end
    
    content_type :json
    
    # Log incoming request
    logger.info "[Request] #{request.request_method} #{request.path}"
    logger.info "[Request] Query params: #{params.inspect}"
    logger.info "[Request] Headers: #{request.env.select { |k, _| k.start_with?('HTTP_') }.inspect}"
    
    # Get access token (support both direct token and OAuth2 flow)
    access_token = get_valid_access_token
    
    unless access_token
      logger.error "[ERROR] No valid access token available!"
      halt 401, json({ error: { message: 'Authentication required. Please complete OAuth2 authorization or set CONSTANT_CONTACT_ACCESS_TOKEN' } })
    end
    
    # Check token expiration
    stored_tokens = TokenStorage.load
    token_expired = false
    
    if stored_tokens && stored_tokens[:expires_at]
      # Use stored expiration time if available
      token_expired = Time.now.to_i >= stored_tokens[:expires_at]
      if !token_expired
        expires_in = stored_tokens[:expires_at] - Time.now.to_i
        logger.info "[Token] Access token valid (expires in #{expires_in} seconds)"
      end
    elsif JWTUtils.token_expired?(access_token)
      # Fall back to JWT expiration check
      token_expired = true
    else
      expires_in = JWTUtils.token_expires_in(access_token)
      logger.info "[Token] Access token valid (expires in #{expires_in} seconds)" if expires_in
    end
    
    if token_expired
      logger.warn "[Token] Access token is expired, attempting refresh..."
      access_token = refresh_access_token_if_needed
      
      unless access_token
        logger.error "[ERROR] Failed to refresh expired token!"
        
        # If refresh failed due to invalid refresh token, provide authorization URL
        client_id = ENV['CONSTANT_CONTACT_CLIENT_ID']
        if client_id
          redirect_uri = ENV['CONSTANT_CONTACT_REDIRECT_URI'] || "#{request.scheme}://#{request.host_with_port}/oauth/callback"
          oauth_client = ConstantContactOAuth2.new(client_id, nil, redirect_uri, logger)
          state = SecureRandom.hex(16)
          auth_url = oauth_client.authorization_url(state, ['contact_data', 'offline_access'])
          
          halt 401, json({ 
            error: { 
              message: 'Access token expired and refresh failed. Re-authorization required.',
              requires_reauth: true,
              authorization_url: auth_url
            } 
          })
        else
          halt 401, json({ error: { message: 'Access token expired and refresh failed. Please re-authorize at /oauth/authorize' } })
        end
      end
    end
    
    logger.info "[Config] Using access token (length: #{access_token.length} chars, first 10: #{access_token[0..10]}...)"
    @api = ConstantContactAPI.new(access_token, logger)
  end

  # OAuth2 Authorization Endpoints
  get '/oauth/authorize' do
    client_id = ENV['CONSTANT_CONTACT_CLIENT_ID']
    redirect_uri = ENV['CONSTANT_CONTACT_REDIRECT_URI'] || "#{request.scheme}://#{request.host_with_port}/oauth/callback"
    
    unless client_id
      content_type :json
      status 500
      return json({ error: { message: 'OAuth2 not configured. Set CONSTANT_CONTACT_CLIENT_ID' } })
    end
    
    # Client secret not needed for authorization step, only for token exchange/refresh
    oauth_client = ConstantContactOAuth2.new(client_id, nil, redirect_uri, logger)
    state = params['state'] || SecureRandom.hex(16)
    auth_url = oauth_client.authorization_url(state, params['scope']&.split(' ') || ['contact_data', 'offline_access'])
    
    # Default behavior: return JSON with authorization URL
    # Use ?redirect=true to perform HTTP redirect instead
    if params['redirect'] == 'true'
      logger.info "[OAuth2] Redirecting to authorization URL: #{auth_url}"
      redirect auth_url
    else
      content_type :json
      logger.info "[OAuth2] Returning authorization URL as JSON: #{auth_url}"
      json({
        authorization_url: auth_url,
        state: state,
        message: 'Visit the authorization_url in a browser to complete OAuth2 flow'
      })
    end
  end

  get '/oauth/callback' do
    code = params['code']
    state = params['state']
    error = params['error']
    
    if error
      logger.error "[OAuth2] Authorization error: #{error}"
      error_message = "OAuth2 authorization failed: #{error}"
      redirect "/oauth/error?error=#{URI.encode_www_form_component(error)}&message=#{URI.encode_www_form_component(error_message)}"
      return
    end
    
    unless code
      logger.error "[OAuth2] No authorization code received"
      error_message = 'No authorization code received'
      redirect "/oauth/error?message=#{URI.encode_www_form_component(error_message)}"
      return
    end
    
    client_id = ENV['CONSTANT_CONTACT_CLIENT_ID']
    client_secret = ENV['CONSTANT_CONTACT_CLIENT_SECRET']
    redirect_uri = ENV['CONSTANT_CONTACT_REDIRECT_URI'] || "#{request.scheme}://#{request.host_with_port}/oauth/callback"
    
    unless client_secret
      logger.error "[OAuth2] Client secret required for token exchange"
      error_message = 'Client secret required for token exchange. Set CONSTANT_CONTACT_CLIENT_SECRET'
      redirect "/oauth/error?message=#{URI.encode_www_form_component(error_message)}"
      return
    end
    
    oauth_client = ConstantContactOAuth2.new(client_id, client_secret, redirect_uri, logger)
    result = oauth_client.exchange_code_for_token(code)
    
    if result[:success]
      token_data = result[:data]
      logger.info "[OAuth2] Successfully obtained tokens"
      
      # Log token info (masked)
      expires_in = token_data['expires_in'] || 'unknown'
      logger.info "[OAuth2] Token expires in: #{expires_in} seconds"
      
      # Store tokens for future use in .tokens.json
      expires_at = Time.now.to_i + (token_data['expires_in'].to_i || 86400)
      TokenStorage.save(
        token_data['access_token'],
        token_data['refresh_token'],
        expires_at
      )
      logger.info "[OAuth2] Tokens saved to #{TokenStorage::TOKEN_FILE}"
      
      # Update .env file with tokens
      env_file = EnvFileUpdater.update_tokens(
        token_data['access_token'],
        token_data['refresh_token'],
        logger
      )
      
      if env_file
        logger.info "[OAuth2] Tokens updated in #{env_file} and runtime environment"
      else
        logger.warn "[OAuth2] Failed to update .env file, but tokens are saved in #{TokenStorage::TOKEN_FILE}"
      end
      
      # Redirect to success page
      redirect '/oauth/success'
    else
      logger.error "[OAuth2] Token exchange failed: #{result[:error].inspect}"
      error_body = result[:error] || {}
      error_message = error_body['error_description'] || error_body['error_message'] || error_body['message'] || 'Token exchange failed'
      redirect "/oauth/error?message=#{URI.encode_www_form_component(error_message)}"
    end
  end

  post '/oauth/refresh' do
    content_type :json
    
    request.body.rewind
    body_content = request.body.read
    begin
      body = body_content && !body_content.empty? ? JSON.parse(body_content) : {}
    rescue JSON::ParserError => e
      logger.error "[OAuth2] JSON parse error in refresh: #{e.message}"
      body = {}
    end
    refresh_token = body['refresh_token'] || ENV['CONSTANT_CONTACT_REFRESH_TOKEN']
    
    # Try stored tokens if no refresh token provided
    if !refresh_token
      stored_tokens = TokenStorage.load
      refresh_token = stored_tokens&.dig(:refresh_token)
    end
    
    unless refresh_token
      status 400
      return json({ error: { message: 'Refresh token required. Provide in request body or complete OAuth flow.' } })
    end
    
    client_id = ENV['CONSTANT_CONTACT_CLIENT_ID']
    client_secret = ENV['CONSTANT_CONTACT_CLIENT_SECRET']
    
    unless client_id && client_secret
      status 500
      return json({ error: { message: 'OAuth2 not configured' } })
    end
    
    oauth_client = ConstantContactOAuth2.new(client_id, client_secret, '', logger)
    result = oauth_client.refresh_token(refresh_token)
    
    if result[:success]
      token_data = result[:data]
      logger.info "[OAuth2] Successfully refreshed tokens"
      
      # Update stored tokens
      expires_at = Time.now.to_i + (token_data['expires_in'].to_i || 86400)
      TokenStorage.save(
        token_data['access_token'],
        token_data['refresh_token'] || refresh_token, # Use new refresh token if provided, otherwise keep old one
        expires_at
      )
      logger.info "[OAuth2] Updated tokens saved to #{TokenStorage::TOKEN_FILE}"
      
      status 200
      json({
        message: 'Token refreshed successfully. Updated tokens have been saved.',
        access_token: token_data['access_token'],
        refresh_token: token_data['refresh_token'],
        expires_in: token_data['expires_in'],
        token_type: token_data['token_type']
      })
    else
      logger.error "[OAuth2] Token refresh failed: #{result[:error].inspect}"
      
      # Check if refresh token is invalid/expired - need to re-authorize
      error_body = result[:error] || {}
      error_key = error_body['error'] || error_body['error_key']
      error_message = error_body['error_description'] || error_body['error_message'] || ''
      
      if error_key == 'invalid_grant' || error_message.include?('refresh token is invalid') || error_message.include?('refresh token is expired')
        logger.warn "[OAuth2] Refresh token is invalid/expired, returning authorization URL"
        
        # Clear invalid tokens
        TokenStorage.clear
        
        # Return authorization URL for re-authorization
        redirect_uri = ENV['CONSTANT_CONTACT_REDIRECT_URI'] || "#{request.scheme}://#{request.host_with_port}/oauth/callback"
        oauth_auth_client = ConstantContactOAuth2.new(client_id, nil, redirect_uri, logger)
        state = SecureRandom.hex(16)
        auth_url = oauth_auth_client.authorization_url(state, ['contact_data', 'offline_access'])
        
        status 401
        return json({
          error: {
            message: 'Refresh token is invalid or expired. Re-authorization required.',
            requires_reauth: true,
            authorization_url: auth_url
          }
        })
      end
      
      status result[:status]
      json(result[:error])
    end
  end

  # Manual token save endpoint (for testing/debugging)
  post '/oauth/tokens' do
    content_type :json
    
    request.body.rewind
    body_content = request.body.read
    begin
      body = body_content && !body_content.empty? ? JSON.parse(body_content) : {}
    rescue JSON::ParserError => e
      logger.error "[OAuth2] JSON parse error in tokens: #{e.message}"
      body = {}
    end
    
    access_token = body['access_token']
    refresh_token = body['refresh_token']
    expires_in = body['expires_in'] || 86400
    
    unless access_token && refresh_token
      status 400
      return json({ error: { message: 'access_token and refresh_token required' } })
    end
    
    expires_at = Time.now.to_i + expires_in.to_i
    TokenStorage.save(access_token, refresh_token, expires_at)
    
    logger.info "[OAuth2] Tokens manually saved to #{TokenStorage::TOKEN_FILE}"
    
    status 200
    json({
      message: 'Tokens saved successfully',
      expires_at: expires_at,
      expires_in: expires_in
    })
  end

  private

  def get_valid_access_token
    # Try direct access token from env first (for manual override)
    access_token = ENV['CONSTANT_CONTACT_ACCESS_TOKEN']
    if access_token && !access_token.empty? && access_token != 'your_access_token_here'
      logger.info "[Token] Using access token from environment variable"
      return access_token
    end
    
    # Try loading stored tokens from file
    stored_tokens = TokenStorage.load
    if stored_tokens && stored_tokens[:access_token]
      # Check if token is expired
      expires_at = stored_tokens[:expires_at] || 0
      if Time.now.to_i < expires_at
        logger.info "[Token] Using stored access token (expires in #{expires_at - Time.now.to_i} seconds)"
        return stored_tokens[:access_token]
      else
        logger.warn "[Token] Stored access token expired, will attempt refresh"
      end
    end
    
    nil
  end

  def refresh_access_token_if_needed
    # Try to get refresh token from stored tokens first
    stored_tokens = TokenStorage.load
    refresh_token = stored_tokens&.dig(:refresh_token) || ENV['CONSTANT_CONTACT_REFRESH_TOKEN']
    
    unless refresh_token
      logger.error "[Token] No refresh token available (checked stored tokens and CONSTANT_CONTACT_REFRESH_TOKEN)"
      return nil
    end
    
    logger.info "[Token] Refresh token found (length: #{refresh_token.length} chars)"
    
    client_id = ENV['CONSTANT_CONTACT_CLIENT_ID']
    client_secret = ENV['CONSTANT_CONTACT_CLIENT_SECRET']
    
    unless client_id
      logger.error "[Token] CLIENT_ID not configured"
      return nil
    end
    
    unless client_secret
      logger.error "[Token] CLIENT_SECRET required for token refresh but not configured"
      return nil
    end
    
    logger.info "[Token] OAuth2 credentials found, attempting token refresh..."
    
    oauth_client = ConstantContactOAuth2.new(client_id, client_secret, nil, logger)
    result = oauth_client.refresh_token(refresh_token)
    
    if result[:success]
      token_data = result[:data]
      logger.info "[Token] Successfully refreshed access token"
      logger.info "[Token] New token expires in: #{token_data['expires_in']} seconds"
      
      # Update stored tokens
      expires_at = Time.now.to_i + (token_data['expires_in'].to_i || 86400)
      if stored_tokens
        TokenStorage.update_access_token(token_data['access_token'], expires_at)
        # Update refresh token if a new one was provided
        if token_data['refresh_token']
          TokenStorage.save(token_data['access_token'], token_data['refresh_token'], expires_at)
        end
      end
      
      token_data['access_token']
    else
      logger.error "[Token] Token refresh failed with status: #{result[:status]}"
      logger.error "[Token] Error details: #{result[:error].inspect}"
      
      # Check if refresh token is invalid/expired
      error_body = result[:error] || {}
      error_key = error_body['error'] || error_body['error_key']
      error_message = error_body['error_description'] || error_body['error_message'] || ''
      
      if error_key == 'invalid_grant' || error_message.include?('refresh token is invalid') || error_message.include?('refresh token is expired')
        logger.warn "[Token] Refresh token is invalid/expired, clearing tokens"
        TokenStorage.clear
      end
      
      nil
    end
  end

  # Frontend Routes
  get '/' do
    send_file File.join(settings.public_folder, 'index.html')
  end

  get '/contacts' do
    # Check if request explicitly wants JSON (API) or HTML (browser)
    accept_header = request.env['HTTP_ACCEPT'].to_s.downcase
    query_string = request.env['QUERY_STRING'].to_s
    
    # If Accept header explicitly includes application/json, treat as API request
    # Also treat requests with query parameters as API requests (browsers navigate without query params)
    has_query_params = !query_string.nil? && !query_string.empty?
    wants_json = accept_header.include?('application/json') || has_query_params
    
    if wants_json
      # API request - continue to API handler below
      pass
    else
      # Browser request - serve HTML page
      send_file File.join(settings.public_folder, 'contacts.html')
    end
  end

  get '/contacts/new' do
    send_file File.join(settings.public_folder, 'contacts', 'new.html')
  end

  get '/contacts/:id/edit' do
    send_file File.join(settings.public_folder, 'contacts', 'edit.html')
  end

  get '/oauth/success' do
    send_file File.join(settings.public_folder, 'oauth', 'success.html')
  end

  get '/oauth/error' do
    send_file File.join(settings.public_folder, 'oauth', 'error.html')
  end

  # Configuration endpoint - serves API_BASE_URL to frontend
  get '/config.js' do
    content_type 'application/javascript'
    api_base_url = (ENV['API_BASE_URL'] || '').gsub("'", "\\'").gsub("\n", "\\n").gsub("\r", "\\r")
    "window.API_BASE_URL = '#{api_base_url}';"
  end

  # Health check
  get '/health' do
    json({ status: 'ok', service: 'constant-contact-api' })
  end

  # Token status check
  get '/oauth/status' do
    content_type :json
    
    access_token = ENV['CONSTANT_CONTACT_ACCESS_TOKEN']
    refresh_token = ENV['CONSTANT_CONTACT_REFRESH_TOKEN']
    client_id = ENV['CONSTANT_CONTACT_CLIENT_ID']
    client_secret = ENV['CONSTANT_CONTACT_CLIENT_SECRET']
    
    status_info = {
      access_token: {
        present: !access_token.nil? && !access_token.empty? && access_token != 'your_access_token_here',
        expired: access_token ? JWTUtils.token_expired?(access_token) : nil,
        expires_in: access_token ? JWTUtils.token_expires_in(access_token) : nil
      },
      refresh_token: {
        present: !refresh_token.nil? && !refresh_token.empty?
      },
      oauth2_configured: !client_id.nil? && !client_secret.nil? && !client_id.empty? && !client_secret.empty?,
      redirect_uri: ENV['CONSTANT_CONTACT_REDIRECT_URI'] || "#{request.scheme}://#{request.host_with_port}/oauth/callback"
    }
    
    json(status_info)
  end

  # GET /contacts - Get all contacts
  # Query params: limit, status, updated_after, include, include_count
  get '/contacts' do
    params_hash = params.to_h.reject { |k, _| k == 'splat' || k == 'captures' }
    logger.info "[Handler] Processing GET /contacts with params: #{params_hash.inspect}"
    
    result = @api.get_contacts(params_hash)
    
    logger.info "[Handler] API result: success=#{result[:success]}, status=#{result[:status]}"
    
    if result[:success]
      status result[:status]
      json(result[:data])
    else
      status result[:status]
      logger.error "[Handler] API Error: #{result[:error].inspect}"
      json(result[:error])
    end
  end

  # GET /contacts/:id - Get a single contact
  get '/contacts/:id' do
    result = @api.get_contact(params[:id])
    
    if result[:success]
      status result[:status]
      json(result[:data])
    else
      status result[:status]
      json(result[:error])
    end
  end

  # POST /contacts - Create a new contact
  post '/contacts' do
    request.body.rewind
    body_content = request.body.read
    
    if body_content.nil? || body_content.empty?
      status 400
      return json({ error: { message: 'Request body is required' } })
    end
    
    begin
      contact_data = JSON.parse(body_content)
    rescue JSON::ParserError => e
      logger.error "[Handler] JSON parse error: #{e.message}"
      logger.error "[Handler] Body content: #{body_content[0..200]}"
      status 400
      return json({ error: { message: 'Invalid JSON', details: e.message } })
    end
    
    result = @api.create_contact(contact_data)
    
    if result[:success]
      status result[:status]
      json(result[:data] || {})
    else
      status result[:status]
      error_data = result[:error] || { message: 'Failed to create contact' }
      json(error_data.is_a?(Hash) ? error_data : { error: error_data })
    end
  rescue => e
    logger.error "[Handler] Error in POST /contacts: #{e.message}"
    logger.error "[Handler] #{e.backtrace.join("\n")}"
    status 500
    json({ error: { message: 'Internal server error', details: e.message } })
  end

  # PUT /contacts/:id - Update a contact
  put '/contacts/:id' do
    request.body.rewind
    body_content = request.body.read
    
    if body_content.nil? || body_content.empty?
      status 400
      return json({ error: { message: 'Request body is required' } })
    end
    
    begin
      contact_data = JSON.parse(body_content)
    rescue JSON::ParserError => e
      logger.error "[Handler] JSON parse error: #{e.message}"
      logger.error "[Handler] Body content: #{body_content[0..200]}"
      status 400
      return json({ error: { message: 'Invalid JSON', details: e.message } })
    end
    
    result = @api.update_contact(params[:id], contact_data)
    
    if result[:success]
      status result[:status]
      json(result[:data] || {})
    else
      status result[:status]
      error_data = result[:error] || { message: 'Failed to update contact' }
      json(error_data.is_a?(Hash) ? error_data : { error: error_data })
    end
  rescue => e
    logger.error "[Handler] Error in PUT /contacts/:id: #{e.message}"
    logger.error "[Handler] #{e.backtrace.join("\n")}"
    status 500
    json({ error: { message: 'Internal server error', details: e.message } })
  end

  # DELETE /contacts/:id - Delete a contact
  delete '/contacts/:id' do
    result = @api.delete_contact(params[:id])
    
    if result[:success]
      status result[:status]
      # For 204 No Content, return empty body (no content-type or body)
      if result[:status] == 204
        status 204
        body ''
      else
        content_type :json
        json({ message: 'Contact deleted successfully' })
      end
    else
      status result[:status]
      content_type :json
      error_data = result[:error] || { message: 'Failed to delete contact' }
      json(error_data.is_a?(Hash) ? error_data : { error: error_data })
    end
  rescue => e
    logger.error "[Handler] Error in DELETE /contacts/:id: #{e.message}"
    logger.error "[Handler] #{e.backtrace.join("\n")}"
    status 500
    content_type :json
    json({ error: { message: 'Internal server error', details: e.message } })
  end

  # Error handling
  error 404 do
    json({ error: { message: 'Not found' } })
  end

  error 500 do
    json({ error: { message: 'Internal server error' } })
  end
end

ConstantContactApp.run! if __FILE__ == $0
