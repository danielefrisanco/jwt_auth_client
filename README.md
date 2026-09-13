# JwtAuthClient

A small, hardened Ruby client for issuing short-lived JWTs and sending them as `Bearer` tokens
between your own services.

- **Token issuing** — `iss`, `sub`, `iat`, `nbf`, `exp`, `jti`, plus optional `aud`, `scopes` and
  custom claims. HMAC only (`HS256`/`HS384`/`HS512`) with enforced key length; `none` is rejected.
- **Faraday client** — a connection that mints a fresh token per request, with timeouts,
  JSON encode/decode, error raising and opt-in retries.
- **`Issuable` mixin** — give a model a `#to_jwt` method (e.g. an SSO hub handing an identity
  token to a client app).
- **Fails at boot, not at runtime** — misconfiguration raises `JwtAuthClient::ConfigurationError`
  from `JwtAuthClient.configure`.

Requires Ruby >= 3.1. Pairs with a verifier such as `rack_jwt_verifier` on the receiving side.

## Installation

```ruby
gem "jwt_auth_client", "~> 0.2"
# optional, only if you enable retries:
# gem "faraday-retry"
```

## Configuration

Configure once at boot (e.g. `config/initializers/jwt_auth_client.rb`). The block is validated
when it returns, so a bad configuration fails the boot.

```ruby
JwtAuthClient.configure do |config|
  # Required. >= 32 bytes for HS256 (48 for HS384, 64 for HS512). Generate with:
  #   openssl rand -hex 32
  # Defaults to ENV["JWT_SERVICE_SECRET"]; there is deliberately NO fallback value.
  config.shared_secret = ENV.fetch("JWT_SERVICE_SECRET")

  # Required. Identifies this application in the `iss` claim.
  config.issuer = "main_app_sso"

  config.algorithm = "HS256"           # HS256 | HS384 | HS512  (default HS256)
  config.default_expiry_seconds = 300  # token lifetime (default 300)

  # Service name => base URL, used by HttpClient. Always use https:// in production.
  config.service_urls = {
    billing_api:   "https://billing.internal",
    user_data_api: "https://users.internal"
  }

  # HTTP timeouts in seconds (defaults: 2 / 5 / 5)
  config.open_timeout  = 2
  config.read_timeout  = 5
  config.write_timeout = 5

  # Optional: reuse a token for up to N seconds instead of signing one per request.
  # 0 (default) = fresh token and fresh `jti` per request, best for replay detection.
  config.token_reuse_seconds = 0

  # Optional: retries (needs the faraday-retry gem). nil (default) = no retries.
  # config.retry_options = { max: 2, interval: 0.1, backoff_factor: 2, retry_statuses: [502, 503, 504] }
end
```

| Setting | Type | Default | Notes |
|---|---|---|---|
| `shared_secret` | String | `ENV["JWT_SERVICE_SECRET"]` | **Required.** Min 32/48/64 bytes for HS256/384/512. |
| `issuer` | String | — | **Required.** The `iss` claim. |
| `algorithm` | String | `"HS256"` | One of `HS256`, `HS384`, `HS512`. |
| `default_expiry_seconds` | Integer | `300` | Token lifetime. |
| `service_urls` | Hash | `{}` | `{ service_name: "https://..." }` |
| `open_timeout` / `read_timeout` / `write_timeout` | Numeric | `2` / `5` / `5` | Seconds. |
| `token_reuse_seconds` | Integer | `0` | Reuse window for a minted token; always re-issued within 30 s of expiry. |
| `retry_options` | Hash / nil | `nil` | Passed to Faraday's `:retry` middleware. |

## Usage

### Authenticated HTTP client

`HttpClient.call` returns a `Faraday::Connection`. Build it once per service and keep it —
the token is issued lazily on each request, so a long-lived connection never sends an expired token.

```ruby
BILLING = JwtAuthClient::HttpClient.call(
  user_id: "service-account-etl",   # `sub` claim
  target_service: :billing_api,     # `aud` claim; must be a key in service_urls
  scopes: ["read:invoices"]         # `scopes` claim
)

response = BILLING.get("/v1/invoices/latest")   # => Faraday::Response, body already parsed
response.body["total"]

BILLING.post("/v1/payments", { amount: 10 })    # body encoded as JSON automatically
```

4xx/5xx responses raise `Faraday::ClientError` / `Faraday::ServerError` with the parsed body available
as `error.response[:body]`.

Override *where* the request goes (a canary host, a test server) without changing *who the token
is for* — `target_service` is always required so every token carries an `aud`:

```ruby
canary = JwtAuthClient::HttpClient.call(
  user_id: "etl", target_service: :billing_api, base_url: "https://billing-canary.internal"
)
```

Add your own middleware (logging, instrumentation) with a block; it runs before the adapter is set:

```ruby
client = JwtAuthClient::HttpClient.call(user_id: "etl", target_service: :billing_api) do |conn|
  conn.response :logger, Rails.logger, headers: false
end
```

A service-specific wrapper keeps call sites short — see [`examples/billing_client.rb`](examples/billing_client.rb):

```ruby
class BillingClient < JwtAuthClient::HttpClient
  def self.call(user_id:, scopes: [], base_url: nil, &block)
    super(user_id: user_id, target_service: :billing_api, scopes: scopes, base_url: base_url, &block)
  end
end
```

### Token only

For non-HTTP transports (message queues, redirects, ...):

```ruby
token = JwtAuthClient::TokenIssuer.call(
  user_id: "system-job-id",
  target_service: :data_pipeline,     # optional `aud`
  scopes: ["process:orders"],         # optional
  claims: { tenant: "acme" },         # optional custom claims (registered claims are protected)
  expiry_seconds: 60                  # optional, overrides default_expiry_seconds
)
```

### `Issuable` — tokens from a model

```ruby
class User < ApplicationRecord
  include JwtAuthClient::Issuable

  def jwt_claims
    { user_id: sso_id, email: email }
  end
end

user.to_jwt                                     # sub = jwt_claims[:user_id] (falls back to #id)
user.to_jwt(expiry_seconds: 60, target_service: :client_app)
```

Override `#jwt_subject` to choose a different `sub`.

### Token payload

```json
{
  "iss": "main_app_sso",
  "sub": "service-account-etl",
  "aud": "billing_api",
  "scopes": ["read:invoices"],
  "iat": 1700000000,
  "nbf": 1700000000,
  "exp": 1700000300,
  "jti": "9c1a3f0e-..."
}
```

## Errors

| Class | Raised when |
|---|---|
| `JwtAuthClient::ConfigurationError` | Configuration is missing/invalid (secret, algorithm, issuer, timeouts, ...). |
| `JwtAuthClient::UnknownServiceError` (< `ConfigurationError`) | `target_service` has no entry in `service_urls` and no `base_url` was given. |
| `JwtAuthClient::TokenError` | The `jwt` gem failed to sign the payload. |
| `ArgumentError` | Bad call arguments (`user_id`/`target_service` blank, invalid `expiry_seconds`, ...). |

All gem errors inherit from `JwtAuthClient::Error`.

## Security notes

- **Transport:** bearer tokens are credentials. Only send them over TLS (or an mTLS service mesh);
  never set `ssl: { verify: false }` on the connection.
- **Secret handling:** load the secret from the environment or a secret manager, rotate it, and never
  commit it. Every service holding the secret can mint tokens for every `aud`, so keep the set of
  holders small. Asymmetric signing (RS256/ES256, private key on the issuer only) is planned.
- **Verifier side:** verify the signature *and* `iss`, `aud`, `exp`, `nbf`; allow a small leeway
  (e.g. 30 s) for clock skew; optionally track `jti` to detect replays.
- **Lifetime:** keep `default_expiry_seconds` short (minutes). Use `expiry_seconds:` for one-off tokens
  that should live even less.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rake build   # builds pkg/jwt_auth_client-x.y.z.gem
```

See [CHANGELOG.md](CHANGELOG.md) for release notes and upgrade steps.

## License

MIT — see [LICENSE](LICENSE).
