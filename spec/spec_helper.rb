# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "jwt_auth_client"
require "jwt"
require "timecop"
require "webmock/rspec"

# A secret long enough for every supported HMAC algorithm (>= 64 bytes).
TEST_SECRET = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.order = :random
  Kernel.srand config.seed

  # Every example starts from a fresh, valid configuration.
  config.before do
    JwtAuthClient.reset_configuration!
    JwtAuthClient.configure do |c|
      c.shared_secret = TEST_SECRET
      c.algorithm = "HS256"
      c.default_expiry_seconds = 300
      c.issuer = "main_app_sso"
      c.service_urls = { billing_api: "http://billing.local" }
    end
  end

  config.after { Timecop.return }
end
