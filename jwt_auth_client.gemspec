$LOAD_PATH.push File.expand_path('lib', __dir__)
# Will create this file next
require 'jwt_auth_client/version' 

Gem::Specification.new do |spec|
  spec.name          = "jwt_auth_client"
  spec.version       = JwtAuthClient::VERSION
  spec.authors       = ["Daniele Frisanco"]
  spec.email         = ["daniele.frisanco@gmail.com"]
  spec.summary       = "Secure client for generating and sending internal service-to-service JWTs."
  spec.description   = "Generates short-lived, signed JWTs for internal API calls authenticated via a shared secret."
  spec.homepage      = "https://github.com/danielefrisanco/jwt_auth_client"
  spec.license       = "MIT"

  # Standard file inclusion block
  spec.files         = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == "jwt_auth_client.gemspec") || f.match(%r{^(test|spec|features)/})
    end
  end
  spec.require_paths = ["lib"]

  # === CORE RUNTIME DEPENDENCIES ===
  # 1. For JWT generation and signing
  spec.add_dependency "jwt", "~> 2.8" 
  # 2. For HTTP client wrapping and middleware
  spec.add_dependency "faraday", "~> 2.9" 
  # 3. ActiveSupport is often necessary for common utilities in a Rails environment
  spec.add_dependency "activesupport", ">= 6.0" 

  # === DEVELOPMENT DEPENDENCIES ===
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "pry"
  
end