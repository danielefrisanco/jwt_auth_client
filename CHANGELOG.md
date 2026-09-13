# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to
[Semantic Versioning](https://semver.org/).

## [0.2.0] - 2026-09-13

Security-hardening release. Several changes are **breaking**; see the upgrade notes below.

### Security
- **No more default secret.** `shared_secret` now defaults to `ENV["JWT_SERVICE_SECRET"]` with no
  literal fallback. A missing, empty or too-short secret raises `ConfigurationError` at
  `JwtAuthClient.configure` time (was: silently signing with `"development_secret"`).
- **Algorithm allow-list.** Only `HS256`, `HS384` and `HS512` are accepted; `none` and anything else
  raise `ConfigurationError` (was: passed straight to `JWT.encode`, so `none` produced unsigned tokens).
- **Minimum key length** enforced per RFC 7518 §3.2 (32/48/64 bytes for HS256/384/512).
- `issuer` is now required (was: silently `"main_sso_app"`).
- Tokens now carry an `nbf` claim (= `iat`).
- `user_id` (the `sub` claim) must be present; `nil`/empty raises `ArgumentError` (was: `"sub": null`).
- Custom claims can never override the registered claims `iss`, `sub`, `iat`, `nbf`, `exp`, `jti`.

### Fixed
- **Expired tokens on long-lived connections.** The JWT was minted once when the connection was built
  and memoised, so any connection held longer than `default_expiry_seconds` sent expired tokens. The
  token is now issued lazily per request (via Faraday's callable authorization header).
- `scopes: nil` raised `NoMethodError`; it is now treated as no scopes.
- JSON response parsing failed with `Faraday::ParsingError` when the `json` gem >= 3.0 was installed
  (Faraday passes a positional options hash that `json` 3 rejects). A small decoder shim forwards
  options as keywords and works with both `json` 2.x and 3.x.
- `raise_error` now runs after JSON parsing, so `Faraday::Error#response[:body]` contains the decoded
  body instead of a raw string.
- Documentation: `HttpClient.call` returns a `Faraday::Connection`, not a response; the README's
  "base_url only" example (which raised `ArgumentError`) has been corrected.

### Added
- `JwtAuthClient::Issuable` mixin: `include` it in a model, define `#jwt_claims`, and call
  `#to_jwt(expiry_seconds: nil, target_service: nil, scopes: [])`.
- `TokenIssuer.call` accepts `claims:` (extra custom claims) and `expiry_seconds:` (per-call override).
- Configurable HTTP timeouts: `open_timeout` (2 s), `read_timeout` (5 s), `write_timeout` (5 s).
- Opt-in retries via `retry_options` (requires the `faraday-retry` gem).
- Opt-in token reuse via `token_reuse_seconds` (default `0` = fresh `jti` per request); tokens are
  always re-issued within 30 s of expiry.
- `HttpClient.call` yields the Faraday connection so callers can add middleware.
- Error hierarchy: `JwtAuthClient::Error` > `ConfigurationError` > `UnknownServiceError`, and `TokenError`.
- `Configuration#validate!` and `JwtAuthClient.reset_configuration!` (handy in test suites).
- `required_ruby_version >= 3.1`, CI matrix on Ruby 3.1–3.4, `rubygems_mfa_required` metadata, LICENSE file.

### Changed
- **`BillingClient` removed from the gem** and moved to `examples/billing_client.rb`. It hard-coded an
  application-specific service into a generic library; copy the example into your app instead.
- `Configuration#base_url_for` raises `UnknownServiceError` (a `ConfigurationError`) instead of `ArgumentError`.
- `activesupport` is no longer a runtime dependency (it was required but never used).
- Development dependencies are declared in the gemspec only; `Gemfile.lock` and built `.gem` files
  are no longer tracked.

### Upgrade notes (0.1.x → 0.2.0)
1. Set a real secret of at least 32 bytes (`openssl rand -hex 32`) in `JWT_SERVICE_SECRET` or
   `config.shared_secret`, and set `config.issuer`. Boot will fail loudly until you do.
2. If you rescued `ArgumentError` around `HttpClient.call` for unknown services, rescue
   `JwtAuthClient::UnknownServiceError` (or `JwtAuthClient::Error`) instead.
3. If you used `JwtAuthClient::BillingClient`, copy `examples/billing_client.rb` into your application.
4. Verifiers should now expect `nbf` and can apply a small leeway (e.g. 30 s) for clock skew.

## [0.1.0] - 2025-10-25

- Initial release: `TokenIssuer`, `Configuration`, `HttpClient`, `BillingClient`.
