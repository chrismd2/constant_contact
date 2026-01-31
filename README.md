# Constant Contact API Wrapper

A Ruby Sinatra-based API wrapper for the Constant Contact V3 API, providing CRUD operations for contacts.

## Features

- **GET /contacts** - List all contacts (with optional filtering)
- **GET /contacts/:id** - Get a single contact by ID
- **POST /contacts** - Create a new contact
- **PUT /contacts/:id** - Update an existing contact
- **DELETE /contacts/:id** - Delete a contact

## Setup

### Prerequisites

- Ruby 3.2+
- Docker and Docker Compose (for containerized deployment)
- Constant Contact API access token

### Local Development

1. **Install dependencies:**
   ```bash
   bundle install
   ```

2. **Configure environment:**
   ```bash
   cp .env-dev .env
   # Edit .env and add your CONSTANT_CONTACT_ACCESS_TOKEN
   ```

3. **Run the application:**
   ```bash
   bundle exec ruby app.rb
   ```

   Or with auto-reload:
   ```bash
   bundle exec rerun 'ruby app.rb'
   ```

### Docker Development

1. **Build and run:**
   ```bash
   docker compose up --build
   ```

2. **Access the API:**
   - Health check: `http://localhost:4567/health`
   - API endpoints: `http://localhost:4567/contacts`

### Integration with christenson_server_host

This service is automatically included in the main `christenson_server_host/docker-compose.yml`. 

To start it with the main project:
```bash
cd /Users/markchristenson/code/christenson_server_host
make up ENV=dev
# or
make up ENV=prod
```

The service will be available on the `christenson` network and can be accessed via nginx if configured.

**Note:** Make sure you have created the `.env-dev` or `.env-prod` file in this directory with your `CONSTANT_CONTACT_ACCESS_TOKEN` before starting the service.

You can also use all the standard Makefile commands:
```bash
make build constant-contact          # Build the service
make up constant-contact             # Start the service
make logs constant-contact           # View logs
make restart constant-contact        # Restart the service
make down constant-contact           # Stop the service
```

## API Endpoints

### Health Check
```
GET /health
```

### Get All Contacts
```
GET /contacts?limit=50&status=all&updated_after=2024-01-01
```

Query Parameters:
- `limit` - Number of results per page (default: 50)
- `status` - Filter by status (all, active, unsubscribed, removed, etc.)
- `updated_after` - Filter contacts updated after this date (ISO-8601 format)
- `include` - Comma-separated list of subresources to include
- `include_count` - Include total count in response

### Get Single Contact
```
GET /contacts/{contact_id}
```

### Create Contact
```
POST /contacts
Content-Type: application/json

{
  "email_address": {
    "address": "user@example.com",
    "permission_to_send": "implicit"
  },
  "first_name": "John",
  "last_name": "Doe",
  "list_memberships": ["list_id_1", "list_id_2"]
}
```

### Update Contact
```
PUT /contacts/{contact_id}
Content-Type: application/json

{
  "first_name": "Jane",
  "last_name": "Smith"
}
```

### Delete Contact
```
DELETE /contacts/{contact_id}
```

## OAuth2 Authentication

The API supports two authentication methods:

### Method 1: Direct Access Token (Quick Testing)
Set `CONSTANT_CONTACT_ACCESS_TOKEN` in your `.env` file with a manually obtained token.

### Method 2: OAuth2 Authorization Code Flow (Recommended)
Use the built-in OAuth2 flow for secure token management:

1. **Configure OAuth2 credentials** in your `.env` file:
   ```
   CONSTANT_CONTACT_CLIENT_ID=your_client_id
   CONSTANT_CONTACT_CLIENT_SECRET=your_client_secret
   CONSTANT_CONTACT_REDIRECT_URI=http://localhost:4567/oauth/callback
   ```

2. **Initiate authorization**:
   ```
   GET /oauth/authorize
   ```
   This returns a JSON response with an `authorization_url` field. Copy this URL and open it in your browser.

3. **Sign in with your Constant Contact account** in the browser. After authorization, you'll be redirected to the callback URL.

4. **Tokens are automatically saved**: The callback endpoint automatically:
   - Saves tokens to `.tokens.json` for immediate use
   - Updates your `.env` file (or `.env-dev`/`.env-prod` if that's what exists) with the new tokens
   - Updates the runtime environment variables

5. **Restart the application** to ensure all services pick up the new tokens from the environment variables.

**Note:** The application will automatically find and update your `.env` file (trying `.env`, `.env-dev`, `.env-prod` in that order). If you want to manually update tokens, you can still copy them from the callback response JSON.

The API automatically checks token expiration and refreshes when needed (if refresh token is configured).

## OAuth2 Endpoints

### GET /oauth/authorize
Initiates the OAuth2 authorization flow. Returns a JSON response with the authorization URL that you should visit in your browser.

**Query Parameters:**
- `state` (optional) - State parameter for CSRF protection
- `scope` (optional) - Space-separated list of scopes (default: `contact_data offline_access`)
- `redirect` (optional) - If set to `true`, performs an HTTP redirect instead of returning JSON

**Response:**
```json
{
  "authorization_url": "https://authz.constantcontact.com/oauth2/default/v1/authorize?...",
  "state": "...",
  "message": "Visit the authorization_url in a browser to complete OAuth2 flow"
}
```

**Usage:**
1. Call `GET /oauth/authorize` to get the authorization URL
2. Copy the `authorization_url` from the response
3. Open it in your browser and sign in with your Constant Contact account
4. After authorization, you'll be redirected to the callback URL
5. Copy the `access_token` and `refresh_token` from the callback response
6. Update your `.env` file with these values

### GET /oauth/callback
Handles the OAuth2 callback from Constant Contact. Exchanges authorization code for tokens.

**Query Parameters:**
- `code` - Authorization code from Constant Contact
- `state` - State parameter (if provided in authorize request)

**Response:**
```json
{
  "message": "Authorization successful. Tokens have been saved to .tokens.json and updated in your .env file.",
  "access_token": "...",
  "refresh_token": "...",
  "expires_in": 28800,
  "token_type": "Bearer",
  "scope": "contact_data offline_access",
  "env_file_updated": true
}
```

**Note:** The tokens are automatically:
- Saved to `.tokens.json` for immediate use by the application
- Updated in your `.env` file (or `.env-dev`/`.env-prod` if that exists)
- Loaded into the runtime environment variables

### POST /oauth/refresh
Refreshes an expired access token using a refresh token.

**Request Body:**
```json
{
  "refresh_token": "your_refresh_token"
}
```

**Response:**
```json
{
  "message": "Token refreshed successfully",
  "access_token": "...",
  "refresh_token": "...",
  "expires_in": 28800,
  "token_type": "Bearer"
}
```

## Environment Variables

### Required (one of the following):
- `CONSTANT_CONTACT_ACCESS_TOKEN` - Direct access token (for quick testing)
- OR `CONSTANT_CONTACT_CLIENT_ID` + `CONSTANT_CONTACT_CLIENT_SECRET` - For OAuth2 flow

### Optional:
- `CONSTANT_CONTACT_REDIRECT_URI` - OAuth2 redirect URI (default: `http://localhost:4567/oauth/callback`)
- `CONSTANT_CONTACT_REFRESH_TOKEN` - Refresh token for automatic token refresh
- `PORT` - Server port (default: 4567)
- `ENV` - Environment label (dev/prod) - not used by app, just for reference

## Constant Contact API Documentation

- [V3 API Technical Overview](https://v3.developer.constantcontact.com/api_guide/v3_technical_overview.html)
- [OAuth2 Authorization Code Flow](https://v3.developer.constantcontact.com/api_guide/server_flow.html)
- [Contacts API Reference](https://developer.constantcontact.com/api_reference/index.html#tag/Contacts)

## Notes

- The API uses OAuth2 authentication with JWT tokens
- Access tokens expire (typically after 8 hours or 1 hour of inactivity)
- Refresh tokens can be used to obtain new access tokens without re-authorization
- The API automatically checks token expiration and can refresh tokens if configured
- All dates should be in ISO-8601 format (YYYY-MM-DDThh:mm:ss.sZ)
- Contact IDs are UUIDs (36 characters with hyphens)
- The wrapper handles errors and returns appropriate HTTP status codes
