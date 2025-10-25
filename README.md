JwtAuthClient
=============

A minimal, robust Ruby client for internal service-to-service authentication using JSON Web Tokens (JWTs).

This gem simplifies the process of creating, signing, and injecting short-lived JWTs into outgoing HTTP requests, ensuring secure communication between your internal microservices.

Features
--------

*   **Token Generation:** Creates industry-standard JWTs with required claims (`iss`, `sub`, `iat`, `exp`, `jti`).
    
*   **Service-Specific Scopes:** Allows injection of custom claims (`aud`, `scopes`) to authorize access for specific target services.
    
*   **Faraday Integration:** Wraps around Faraday to automatically attach the generated JWT as a `Bearer` token in the `Authorization` header.
    
*   **High-Level Clients:** Supports creating specialized clients (e.g., `BillingClient`) for clean API consumption.
    

Installation
------------

Add this line to your application's Gemfile:

```ruby
gem 'jwt_auth_client', '~> 0.1.0'
```

And then execute:

```bash
$ bundle install
```

Configuration
-------------

You must configure the client once in your application's initialization file (e.g., `config/initializers/jwt_auth_client.rb` in a Rails app).

Setting | Type | Description |
 | - | - | - |
 | **shared_secret** | String | The cryptographic key known to all services (used for signing and verification). **CRITICAL.**
 | **algorithm** | String | The JWT signing algorithm (e.g., '`HS256`').
 | **default_expiry_seconds** | Integer | Default lifespan for the tokens (e.g., `300` seconds = 5 minutes).
 | **issuer** | String | The identifier of the application issuing the token (e.g., '`main_sso_app`').
 | **service_urls** | Hash | Map of internal service keys to their base URLs.

```ruby
# config/initializers/jwt_auth_client.rb

JwtAuthClient.configure do |config|
  # Load the secret from an environment variable!
  config.shared_secret = ENV.fetch('JWT_SERVICE_SECRET') { 'a_fallback_secret_for_dev' }
  config.algorithm = 'HS256'
  config.default_expiry_seconds = 300 # 5 minutes
  config.issuer = 'main_app_sso'
  # Configure base URLs for your internal services
  config.service_urls = {
    billing_api: 'http://billing-service.internal',
    user_data_api: 'http://user-service.internal'
  }
end
```

Usage
-----

### 1\. High-Level Service Client (Recommended)

Use the built-in or custom client wrappers for clean dependency management. These clients automatically use the configured `target_service`.

```ruby
# The BillingClient is a specialized wrapper around HttpClient
# it defaults target_service to :billing_api 
client = JwtAuthClient::BillingClient.call(
  user_id: 'user-id-456',
  scopes: ['read:invoices', 'write:payments']
)

# client is a Faraday connection object
response = client.get('/v1/invoices/latest')
if response.success?
  puts "Invoices: #{response.body}"
end
```

### 2\. General HTTP Client (Advanced)

If you need dynamic control over the target service, you can use the base `HttpClient`.

```ruby
client = JwtAuthClient::HttpClient.call(
  user_id: 'service-account-etl',
  target_service: :user_data_api, # Must be a key defined in service_urls
  scopes: ['read:all_users']
)
# Override the base URL dynamically if needed
override_client = JwtAuthClient::HttpClient.call(
  user_id: 'guest',
  base_url: 'http://temporary-api.test' # Overrides configured service_urls
)
```

### 3\. Token Generation Only

If you only need the raw JWT string for non-HTTP purposes (e.g., message queues), use the `TokenIssuer`.

```ruby
token = JwtAuthClient::TokenIssuer.call(
  user_id: 'system-job-id',
  target_service: 'data_pipeline',
  scopes: ['process:orders']
)
# token will be the signed JWT string
# puts token
```