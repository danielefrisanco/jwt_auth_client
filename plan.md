# jwt_auth_client — Review Findings & Improvement Plan

Scope: `lib/`, `spec/`, gemspec/Gemfile/Rakefile, README. Reviewed on 2026-09-13 against
`main` (`e161b17`). Specs were run with `jwt` 2.x / `json` 2.x: **14 examples, 0 failures**.

Severity legend: **P0** must fix before any production use · **P1** fix soon · **P2** worthwhile
improvement · **P3** nice to have.

---

## 1. Security

### S1 (P0) — Hard-coded fallback secret `"development_secret"`
`lib/jwt_auth_client/configuration.rb:23` sets
`@shared_secret = ENV['JWT_SERVICE_SECRET'] || 'development_secret'`.
If the env var is missing in *any* environment (staging, a misconfigured pod, a CI job), the
gem silently signs production tokens with a public, guessable key. The README example
(`ENV.fetch(...) { 'a_fallback_secret_for_dev' }`) encourages the same anti-pattern.

**Fix**
- Default `@shared_secret = nil`; never fall back to a literal.
- Add `Configuration#validate!` (called lazily by `TokenIssuer`/`HttpClient`, or eagerly from
  `JwtAuthClient.configure`) that raises `JwtAuthClient::ConfigurationError` when the secret is
  `nil`/empty.
- Enforce a minimum key length for HMAC algorithms (≥ 32 bytes for HS256, per RFC 7518 §3.2);
  raise on shorter keys.
- Update README to remove the fallback and show `ENV.fetch('JWT_SERVICE_SECRET')` (no block).

### S2 (P0) — `algorithm` is unvalidated; `'none'` mints unsigned tokens
`Configuration#algorithm` is a free-form string passed straight to `JWT.encode`. Verified:
setting `algorithm = 'none'` produces a 2‑segment token with no signature and no error.
Anything a verifier accepts as `none`/weak becomes a full auth bypass.

**Fix**
- Whitelist in `Configuration`: `ALLOWED_ALGORITHMS = %w[HS256 HS384 HS512 RS256 RS384 RS512 ES256 ES384 ES512].freeze`;
  reject anything else in `validate!`. Explicitly reject `none`.

### S3 (P1) — Symmetric shared secret means every service can impersonate every other
Design note rather than a code bug: a single HS256 secret shared by all services means a
compromised *consumer* can mint tokens for any `aud`/`sub`/`scopes`. Given the gem already
sets `iss`/`aud`, moving to asymmetric signing (RS256/ES256, private key on the issuer only,
public key or JWKS on verifiers) is the natural next step and pairs with the sibling
`rack_jwt_verifier` gem.

**Fix (follow-up, larger scope)**
- Accept `signing_key` (OpenSSL::PKey) in addition to `shared_secret`; pick key material based
  on algorithm family. Add `kid` header support so keys can rotate.

### S4 (P1) — Unvalidated inputs produce misleading or dangerous tokens
Verified behaviour:
- `user_id: nil` → token issued with `"sub": null`.
- `shared_secret = ''` → raises `JWT::DecodeError: HMAC key cannot be empty` on **encode**
  (confusing error class).
- `target_service` is required as a keyword in `HttpClient.call` but may be `nil`, which then
  crashes in `base_url_for` with `NoMethodError` on `nil.to_sym`.

**Fix**
- In `TokenIssuer#initialize`, raise `ArgumentError` when `user_id` is nil/empty.
- Wrap `JWT.encode` and re-raise as `JwtAuthClient::TokenError` with a clear message.
- In `Configuration#base_url_for`, guard `nil`/empty `target_service`.

### S5 (P2) — No `nbf`, no configurable leeway, no per-call expiry
`TokenIssuer#build_payload` (`token_issuer.rb:36-58`) emits `iat`/`exp` only. Add `nbf = iat`
(cheap, standard) and let callers pass `expiry_seconds:` to override the default for very
short-lived tokens. Document that verifiers should apply a small leeway (e.g. 30 s).

### S6 (P2) — Transport guidance
README examples use `http://` base URLs. Add a note that bearer tokens must only be sent over
TLS (or an mTLS/service-mesh internal network) and that Faraday's SSL verification must stay
enabled (never `ssl: { verify: false }`).

### S7 (P3) — Gem publishing hygiene
- Add `spec.metadata['rubygems_mfa_required'] = 'true'`.
- Add `spec.required_ruby_version` (see B2).

---

## 2. Bugs

### B1 (P0) — Token is minted once per connection and never refreshed
`http_client.rb:37` does `conn.request :authorization, 'Bearer', jwt_token` where `jwt_token`
is memoized (`http_client.rb:56`). The connection is the public return value of `.call`, so any
caller that keeps it (a memoized service object, a class-level constant, a connection pool)
will start sending **expired** tokens after `default_expiry_seconds` (5 min). This is the most
likely real-world failure mode of the gem.

**Fix** — Faraday's `:authorization` middleware accepts a callable and evaluates it per
request (verified in faraday 2.14: `header_from` calls `value.call`):
```ruby
conn.request :authorization, 'Bearer', -> { issue_token }
```
Optionally cache the token and re-issue only when `exp - now < refresh_margin` (e.g. 30 s) to
avoid an HMAC + UUID per request on hot paths (see P1 below).

### B2 (P0) — Test suite cannot run via Bundler on the workspace Ruby
`Gemfile.lock` pins `activesupport 8.1.0` (requires Ruby ≥ 3.2) but the workspace
`.ruby-version` is 3.1.4; `bundle exec rspec` fails with `Bundler::GemNotFound` on every
installed Ruby. There is no `required_ruby_version`, no project `.ruby-version`, and no CI.

**Fix**
- Add `spec.required_ruby_version = ">= 3.1"` (or `>= 3.2` and bump `.ruby-version`).
- Add a project `.ruby-version` matching the lockfile, or drop `Gemfile.lock` from git (usual
  practice for gems) and let consumers resolve.
- Add a GitHub Actions matrix (Ruby 3.1–3.4) running `bundle exec rspec`.

### B3 (P1) — `scopes: nil` raises `NoMethodError`
`token_issuer.rb:55` calls `@scopes.empty?`. The spec is titled "handles nil scopes" but only
tests the default `[]`. **Fix**: `Array(@scopes)` in `initialize` and add a real nil test.

### B4 (P1) — README documents an invocation that raises
README "General HTTP Client" example: `HttpClient.call(user_id: 'guest', base_url: ...)` omits
the required `target_service:` keyword → `ArgumentError: missing keyword`. Either make
`target_service` optional when `base_url` is given (then `aud` is omitted) or fix the example.

### B5 (P2) — `raise_error` runs before JSON parsing
Middleware order in `http_client.rb:40-42` is `json (response)` then `raise_error`. Response
middleware unwinds inner→outer, so `raise_error` sees the raw body and
`Faraday::ClientError#response[:body]` is an unparsed string. Declare `conn.response :raise_error`
**before** `conn.response :json` so error objects carry parsed bodies.

### B6 (P2) — Doc/behaviour mismatches
- `HttpClient.call` YARD says `@return [Faraday::Response]`; it returns a `Faraday::Connection`.
- `lib/jwt_auth_client.rb:10-16` defines `module JwtAuthClient` twice.
- `content_type: /\bjson$/` on `response :json` is already Faraday's default — drop it.

### B8 (P1) — Response JSON parsing breaks with `json` >= 3.0
`json 3.0` (resolved by a fresh `bundle install` today) removed the positional options hash from
`JSON.parse`; Faraday 2.14.3's `Response::Json` still calls `JSON.parse(body, {})`, so every JSON
response raises `Faraday::ParsingError: wrong number of arguments`. Affects consumers, not just
specs. **Fix**: pass a decoder shim via `parser_options: { decoder: [JwtAuthClient::JsonDecoder, :parse] }`
that forwards options as keywords (works on json 2.x and 3.x). Re-evaluate once Faraday ships a fix.

### B7 (P2) — Global config mutation leaks between spec files
`spec/jwt_auth_client/http_client_spec.rb:16-25` reconfigures the singleton and never resets it;
`token_issuer_spec.rb` stubs `JwtAuthClient.configuration` with an `OpenStruct`. Pass/fail is
order-dependent. **Fix**: add `JwtAuthClient.reset_configuration!` and call it in a global
`config.before(:each)`; use a real `Configuration` in specs instead of `OpenStruct`.

---

## 3. Performance / Reliability

### P1 (P1) — No timeouts on the Faraday connection
`Faraday.new(url: ...)` inherits adapter defaults (Net::HTTP: 60 s open/read). A stalled
downstream service pins a Puma/Sidekiq thread for a minute. Add configurable
`open_timeout`/`read_timeout`/`write_timeout` (sensible defaults: 2 s / 5 s / 5 s) to
`Configuration` and apply them via `conn.options`.

### P2 (P1) — A new `Faraday::Connection` (and TCP connection) per `.call`
`HttpClient.call` builds a fresh connection each time; there is no keep‑alive reuse. For
chatty service-to-service traffic this is the dominant cost (TCP + TLS handshake per call).
Once B1 is fixed (per-request token), connections become safe to keep alive:
- Document "build once per service, reuse" as the intended pattern.
- Optionally cache connections per `(target_service, base_url)` inside the gem and support
  `faraday-net_http_persistent` as an opt-in adapter.

### P3 (P2) — Token generation cost on hot paths
After B1, each request does `SecureRandom.uuid` + JSON + HMAC — cheap (~20 µs) but nonzero.
Cache the last token per client and reuse it until `exp - refresh_margin`. Note the trade-off:
reusing `jti` across requests weakens replay detection on the verifier side; make the margin
configurable and default to a short window.

### P4 (P2) — Retries
`faraday-retry` is in the Gemfile but unused. Offer an opt-in `retry` block in `Configuration`
(idempotent methods only, exponential backoff, retry on 5xx/`Faraday::TimeoutError`).

### P5 (P2) — Drop the `activesupport` runtime dependency
`lib/jwt_auth_client.rb:2` requires `active_support/core_ext/numeric/time` for "`N.minutes`
logic" that the library never uses (only a spec uses `.seconds`). ActiveSupport is a heavy
transitive dependency for a gem whose job is one HMAC; removing it also unblocks the lockfile
problem in B2. Replace `expiry_seconds.seconds` in the spec with plain integer arithmetic.

---

## 4. Maintainability / DX

### M1 (P1) — Dependency declarations are inconsistent
- `Gemfile` re-declares `faraday '~> 2.7'` while gemspec says `'~> 2.9'`; re-declares `rspec`
  and `pry` already in the gemspec.
- `webmock` and `timecop` are used by specs but only in the Gemfile, not
  `add_development_dependency`.
- `faraday-typhoeus` and `faraday-retry` are declared but unused.
**Fix**: single source of truth in the gemspec; Gemfile = `source` + `gemspec` only.

### M2 (P1) — Repo hygiene
- No `.gitignore`; `pkg/jwt_auth_client-0.1.0.gem` is tracked and currently dirty in the working
  tree. Add `.gitignore` (`pkg/`, `.bundle/`, `Gemfile.lock` if untracked, `*.gem`,
  `coverage/`) and `git rm --cached pkg/*.gem`.
- `Rakefile` loads both `bundler/gem_tasks` and `Gem::PackageTask` (duplicate `build`/`package`
  tasks) and requires the unused `rake/testtask`. Keep `bundler/gem_tasks` + RSpec task only.
- Add `CHANGELOG.md`, `LICENSE` (gemspec says MIT but no file), `.rubocop.yml`, CI workflow.

### M3 (P2) — Error hierarchy
Introduce `JwtAuthClient::Error < StandardError`, `ConfigurationError`, `TokenError`,
`UnknownServiceError` so callers can rescue precisely instead of catching `ArgumentError` /
`JWT::DecodeError`.

### M4 (P2) — Extensibility hook for the Faraday stack
Let `HttpClient.call` accept a block yielded the connection builder (add logging, instrumentation,
custom middleware) instead of forcing subclassing:
```ruby
JwtAuthClient::HttpClient.call(user_id:, target_service:) { |conn| conn.response :logger }
```

### M5 (P2) — `BillingClient` is app-specific → move to `examples/`
A billing-specific client inside a generic auth gem couples the library to one consumer.
Verified no dependents: no repo in the workspace and no installed gem references `BillingClient`;
the commit that introduced it describes it as demonstrating "the inheritance pattern". **Decision:**
move it to `examples/billing_client.rb` (not shipped in the gem), document the subclass pattern in
the README, and list the removal as a breaking change in 0.2.0.

### M7 (P1) — Missing `JwtAuthClient::Issuable` mixin that `SecureSSOHub` depends on
`SecureSSOHub/app/models/user.rb:13` does `include JwtAuthClient::Issuable` and calls
`user.to_jwt` (controller + test), with a comment saying the module comes from this gem. It never
existed here (`git log -S Issuable` across all branches is empty) nor in any installed gem, so that
app currently fails at boot with `NameError`. The expected payload is `user_id`, `email`,
`iss`, `iat`, `exp` — a user-facing SSO token, not the S2S shape `TokenIssuer` emits.

**Fix** — add a thin mixin built on `TokenIssuer`:
```ruby
class User < ApplicationRecord
  include JwtAuthClient::Issuable
  def jwt_claims = { user_id: sso_id, email: email }  # model-defined claims
end
user.to_jwt                      # signed JWT with iss/iat/exp/nbf/jti + jwt_claims
user.to_jwt(expiry_seconds: 60)  # optional per-call override
```
`jwt_claims` is the only required hook; `sub` defaults to `jwt_claims[:user_id] || id`.
Standard claims are never overridable by `jwt_claims` (iss/iat/exp/nbf/jti win). Spec it, and
document it as the "SSO / user token" use case alongside the S2S one.

### M6 (P3) — Spec quality
- `WebMock.enable!` at file top-level → move to `spec_helper` with `require 'webmock/rspec'`.
- Capturing headers via `@request_headers` ivar inside a `stub_request` block → use
  `a_request(...).with(headers: ...)` matchers.
- Add specs for: expired-token refresh (Timecop travel > expiry), `scopes: nil`, `nil` secret,
  `algorithm: 'none'` rejection, timeouts, middleware ordering (error body parsed).

---

## 5. Execution Plan (ordered)

**Status (2026-09-13):** steps 1–6 are implemented and released as 0.2.0 in the working tree
(uncommitted). 53 specs pass on Ruby 3.1.4 and 3.4.10. Remaining: step 7 (S3, asymmetric signing)
and the `SecureSSOHub` follow-up below.


| Step | Items | Est. | Notes |
|---|---|---|---|
| ✅ 1 | B2, M1, M2, P5, B8 | 1–2 h | Make the suite runnable: fix deps, drop ActiveSupport, add `.gitignore`/`.ruby-version`/CI. Gate for everything else. |
| ✅ 2 | S1, S2, S4, M3, B7 | 2 h | Config validation (`validate!`, algorithm whitelist, min key length), error classes, no default secret. Breaking: secret is now required (released as part of 0.2.0 in step 6). |
| ✅ 3 | B1, B3, B5, B6 | 1–2 h | Per-request token via callable, `Array(scopes)`, middleware order, doc fixes. |
| ✅ 4 | P1, P2, P4 | 2 h | Timeouts, connection reuse guidance/caching, opt-in retry. |
| ✅ 5 | B4, M6, S6 | 1–2 h | README rewrite, spec isolation (`reset_configuration!`), new specs, TLS guidance. |
| ✅ 6 | S5, M4, M5, M7, P3, S7 | 3 h | `nbf`/per-call expiry, connection block hook, move `BillingClient` to `examples/`, add `Issuable` mixin, token cache, MFA metadata. Release **0.2.0** (single release covering steps 1–6). |
| ⬜ 7 | S3 | later | Asymmetric signing + `kid`; coordinate with `rack_jwt_verifier`. **1.0.0** candidate. |

Each step is independently shippable; steps 1–3 close all P0 findings.

### Follow-up outside this repo
- `SecureSSOHub` must add `config/initializers/jwt_auth_client.rb` setting `shared_secret`
  (>= 32 bytes) and `issuer = "SecuressoHub"` (its test asserts that `iss`), then bump to
  `jwt_auth_client ~> 0.2`. Its `User#jwt_claims` should return `{ user_id: sso_id, email: email }`.

## 6. Verification checklist
- ✅ `bundle exec rspec` green locally on 3.1.4 and 3.4.10; CI workflow added for 3.1–3.4.
- ✅ New spec: a connection created at T0 makes a valid request at T0 + expiry + 1 s (proves B1).
- ✅ `JwtAuthClient.configure { |c| c.algorithm = 'none' }` raises `ConfigurationError`.
- ✅ `JwtAuthClient.configure { |c| c.shared_secret = 'short' }` raises `ConfigurationError`.
- ✅ `gem build` ships only `lib/`, README, CHANGELOG, LICENSE (verified with `tar -t`).
