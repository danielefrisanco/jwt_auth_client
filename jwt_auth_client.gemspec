# frozen_string_literal: true

require_relative "lib/jwt_auth_client/version"

Gem::Specification.new do |spec|
  spec.name          = "jwt_auth_client"
  spec.version       = JwtAuthClient::VERSION
  spec.authors       = ["Daniele Frisanco"]
  spec.email         = ["daniele.frisanco@gmail.com"]
  spec.summary       = "Secure client for generating and sending internal service-to-service JWTs."
  spec.description   = "Generates short-lived, signed JWTs for internal API calls and injects them " \
                       "into Faraday requests as Bearer tokens."
  spec.homepage      = "https://github.com/danielefrisanco/jwt_auth_client"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.9"
  spec.add_dependency "jwt", "~> 2.8"

  spec.add_development_dependency "faraday-retry", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "timecop", "~> 0.9"
  spec.add_development_dependency "webmock", "~> 3.19"
end
