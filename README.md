# Constant Contact API Wrapper

A Ruby Sinatra-based API wrapper for the Constant Contact V3 API, providing CRUD operations for contacts.

## Features

- **GET /contacts** - List all contacts (with optional filtering)
- **GET /contacts/:id** - Get a single contact by ID
- **POST /contacts** - Create a new contact
- **PUT /contacts/:id** - Update an existing contact
- **DELETE /contacts/:id** - Delete a contact
- **OAuth2 Authentication** - Built-in OAuth2 flow for secure token management

## Quick Start (Standalone)

The easiest way to run this service is using Docker Compose:

1. **Download/clone the repository:**
   ```bash
   cd /path/to/constant_contact
   ```

2. **Copy the example environment file:**
   ```bash
   cp example.env .env
   ```

3. **Edit `.env` and add your Constant Contact credentials:**
   - Required: Set `CONSTANT_CONTACT_CLIENT_ID` and `CONSTANT_CONTACT_CLIENT_SECRET` for OAuth2 flow
   - Get credentials and set redirect URI at: https://developer.constantcontact.com/
   - See [Environment Variables](#environment-variables) section for details

4. **Start the service:**
   ```bash
   docker compose up
   ```

5. **Access the Service:**
   - Health check: `http://localhost:4567/health`
   - Contacts (frontend and API): `http://localhost:4567/contacts`
   - Add/Edit contact (frontend pages):  
     - New contact form: `http://localhost:4567/contacts/new`  
     - Edit contact form: `http://localhost:4567/contacts/{id}/edit`
   - OAuth authorization and login: `http://localhost:4567/oauth/authorize`

**Notes:**
- The `/contacts` route serves both the browser-based frontend and the API, depending on request type (`Accept: application/json` or query params returns JSON, otherwise HTML).
- `/contacts/new` and `/contacts/{id}/edit` are HTML pages for creating and editing contacts in the browser.
- API endpoints (for use with tools like `curl` or a frontend app) are available at `/contacts`, `/contacts/:id` (GET/POST/PUT/DELETE), matching the documented CRUD routes below.
- For OAuth, browse directly to `/oauth/authorize` to start the login/consent process when tokens are missing or expired.

The service will be running on port `4567` by default.

## Integration with Existing Projects

This service can be integrated into your existing Docker Compose setup. The following sections provide a complete guide for integration.

### Basic Integration

Add the following service definition to your main `docker-compose.yml`:

```yaml
constant_contact:
  env_file:
    - /path/to/constant_contact/.env  # Adjust path to your constant_contact directory
  build:
    context: /path/to/constant_contact/  # Adjust path to your constant_contact directory
    dockerfile: Dockerfile
  container_name: constant_contact-api
  expose:
    - "4567"
  volumes:
    - /path/to/constant_contact/:/app/  # Adjust path to your constant_contact directory
  environment:
    - PORT=4567
    # Set redirect URI to include your API prefix for OAuth callbacks
    - CONSTANT_CONTACT_REDIRECT_URI=https://yourdomain.com/constant_contact/oauth/callback
    - API_BASE_URL=/constant_contact
  networks:
    - your_network_name  # Use your existing Docker network name
  restart: unless-stopped
```

**Note:** Adjust all paths (`/path/to/constant_contact/`) to match your actual directory structure. Paths can be relative (e.g., `../constant_contact/`) or absolute.

### Reverse Proxy Configuration (nginx)

If you're using nginx as a reverse proxy, add a location block to route traffic to the service:

```nginx
location /constant_contact/ {
    proxy_pass http://constant_contact:4567/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    # The `rewrite` directive removes whatever prefix matches your API base path (as set by the `API_BASE_URL` environment variable, e.g., `/constant_contact/`).
    # This ensures requests forwarded to the service use routes like `/contacts` (not prefixed), as expected by the application.
    # When changing the base path in your environment, update both your `API_BASE_URL` env variable and the nginx location/rewrite rules to match that prefix.
    # Remove the /constant_contact prefix before forwarding
    rewrite ^/constant_contact/(.*) /$1 break;
}
```
### Complete Integration Example

Here's a complete example showing integration with a typical multi-service setup:

```yaml
name: my_project
services:
  # Your existing services (postgres, nginx, etc.)
  postgres:
    # ... your postgres configuration

  nginx:
    image: nginx:mainline
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/sites-available:/etc/nginx/sites-available:ro
    networks:
      - app_network
    depends_on:
      - constant_contact
      # ... other dependencies

  constant_contact:
    env_file:
      - ../constant_contact/.env
    build:
      context: ../constant_contact/
      dockerfile: Dockerfile
    container_name: constant_contact-api
    expose:
      - "4567"
    volumes:
      - ../constant_contact/:/app/
    environment:
      - PORT=4567
      - CONSTANT_CONTACT_REDIRECT_URI=https://yourdomain.com/constant_contact/oauth/callback
      - API_BASE_URL=/constant_contact
    networks:
      - app_network
    restart: unless-stopped

networks:
  app_network:
    driver: bridge
```

### Key Integration Points

1. **Environment File**: The service automatically looks for and updates its own `.env`.

2. **Network Configuration**: Ensure the service is on the same Docker network as your reverse proxy (nginx, traefik, etc.) so they can communicate.

3. **OAuth Redirect URI**: When integrating behind a reverse proxy, update `CONSTANT_CONTACT_REDIRECT_URI` to match your public URL structure. This must match the redirect URI configured in your Constant Contact developer account.

4. **API Base Path**: If running behind a reverse proxy with a subpath (e.g., `/constant_contact/`), set `API_BASE_URL` environment variable to `/constant_contact` (no trailing slash). This ensures the frontend JavaScript correctly constructs API URLs.

**Note:** If deploying behind nginx (or another reverse proxy), your rewrite rules must strip the `/constant_contact` prefix before forwarding requests to the API service. This ensures the backend receives URLs in the expected format (e.g., `/contacts` instead of `/constant_contact/contacts`).  

### OAuth Setup for Integration

When integrating behind a reverse proxy:

1. **Configure Redirect URI in Constant Contact Developer Portal**:
   - Go to https://developer.constantcontact.com/
   - Set the redirect URI to: `https://yourdomain.com/constant_contact/oauth/callback`
   - This must exactly match the `CONSTANT_CONTACT_REDIRECT_URI` environment variable

2. **Environment Variables**:
   ```bash
   CONSTANT_CONTACT_CLIENT_ID=your_client_id
   CONSTANT_CONTACT_CLIENT_SECRET=your_client_secret
   CONSTANT_CONTACT_REDIRECT_URI=https://yourdomain.com/constant_contact/oauth/callback
   API_BASE_URL=/constant_contact
   ```

3. **Test OAuth Flow**:
   - Navigate to `https://yourdomain.com/constant_contact/oauth/authorize`
   - Complete the OAuth authorization flow
   - Tokens will be automatically saved to `.env` file on Docker container

### Prerequisites for Integration

- Docker and Docker Compose
- Constant Contact API credentials (Client ID and Secret)
- Access to your main project's `docker-compose.yml` file
- Reverse proxy (nginx, traefik, etc.) if exposing via subpath
- SSL certificate if using HTTPS (recommended for OAuth)

## Local Development (Without Docker)

If you prefer to run the application directly without Docker:

### Prerequisites

- Ruby 3.2+
- Bundler gem

### Setup

1. **Install dependencies:**
   ```bash
   bundle install
   ```

2. **Configure environment:**
   ```bash
   cp example.env .env
   # Edit .env and add your Constant Contact credentials
   ```

3. **Run the application:**
   ```bash
   bundle exec ruby app.rb
   ```

   Or with auto-reload (requires `rerun` gem):
   ```bash
   bundle exec rerun 'ruby app.rb'
   ```

4. **Access the API:**
   - Health check: `http://localhost:4567/health`
   - API endpoints: `http://localhost:4567/contacts`

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

The API uses OAuth2 Authorization Code Flow for secure token management:

1. **Configure OAuth2 credentials** in your `.env` file:
   ```
   CONSTANT_CONTACT_CLIENT_ID=your_client_id
   CONSTANT_CONTACT_CLIENT_SECRET=your_client_secret
   CONSTANT_CONTACT_REDIRECT_URI=http://localhost:4567/oauth/callback
   ```
   Get your Client ID and Secret from: https://developer.constantcontact.com/

2. **Initiate authorization**:
   ```
   GET /oauth/authorize
   ```
   This returns a JSON response with an `authorization_url` field. Copy this URL and open it in your browser.

3. **Sign in with your Constant Contact account** in the browser. After authorization, you'll be redirected to the callback URL.

4. **Tokens are automatically saved**: The callback endpoint automatically:
   - Saves tokens to `.tokens.json` for immediate use
   - Updates your `.env` file
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
5. Tokens are automatically saved to your `.env` file (no manual copying needed)

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

All environment variables are configured in the `.env` file. Start by copying `example.env` to `.env`:

```bash
cp example.env .env
```

### Required:

- **`CONSTANT_CONTACT_CLIENT_ID`** - OAuth2 Client ID
  - Get this from: https://developer.constantcontact.com/
  
- **`CONSTANT_CONTACT_CLIENT_SECRET`** - OAuth2 Client Secret
  - Get this from: https://developer.constantcontact.com/

- **`CONSTANT_CONTACT_REDIRECT_URI`** - OAuth2 redirect URI (default: `http://localhost:4567/oauth/callback`)
  - For standalone: `http://localhost:4567/oauth/callback`
  - For integration: `https://yourdomain.com/constant_contact/oauth/callback`

- **`CONSTANT_CONTACT_REFRESH_TOKEN`** - Refresh token for automatic token refresh
  - Obtained automatically during OAuth2 flow
  - Allows the app to refresh expired access tokens without re-authorization

- **`PORT`** - Server port (default: 4567)
  - Change this if port 4567 is already in use

- **`API_BASE_URL`** - Base path for API routes (for reverse proxy deployments)
  - Leave blank for standalone: `""` or unset
  - Set for integration: `/constant_contact` (no trailing slash)

- **`ENV`** - Environment label (dev/prod) - not used by app, just for reference

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
