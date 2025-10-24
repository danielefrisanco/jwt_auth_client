require 'jwt'
require 'securerandom'

module JwtAuthClient
  class TokenIssuer
    # This is the ONLY public class method API. It initializes and calls the public instance method.
    def self.call(user_id:, target_service: nil, scopes: [])
      new(user_id, target_service, scopes).issue 
    end

    # initialize is public by default.
    def initialize(user_id, target_service, scopes)
      @user_id = user_id
      @target_service = target_service
      @scopes = scopes
      @config = JwtAuthClient.configuration
    end

    # --- Public Instance Method (Called by self.call) ---
    def issue
      encode
    end

    # --- Private Helper Methods ---
    private
    
    def encode
      payload = build_payload
      
      # Use the JWT gem to encode the token
      JWT.encode(payload, @config.shared_secret, @config.algorithm)
    end

    # Uses conditional merging to ensure keys for optional claims (aud, scopes)
    # are only included if they have a non-nil/non-empty value.
    def build_payload
      # Standard JWT Claims (Must include these for security/verification)
      issued_at = Time.now.to_i
      expiry = issued_at + @config.default_expiry_seconds

      # 1. Start with Required Claims
      payload = {
        iss: @config.issuer,                      # Issuer (e.g., main_sso_app)
        sub: @user_id,                            # Subject (The user being impersonated)
        iat: issued_at,                           # Issued At Time
        exp: expiry,                              # Expiration Time (CRITICAL: short-lived)
        jti: SecureRandom.uuid,                   # JWT ID (For optional replay attack prevention)
      }
      
      # 2. Conditionally merge Optional Claims
      # Audience is nil by default
      payload[:aud] = @target_service if @target_service
      
      # Scopes are [] by default, so check if the array is not empty
      payload[:scopes] = @scopes unless @scopes.empty?

      payload
    end
  end
end
