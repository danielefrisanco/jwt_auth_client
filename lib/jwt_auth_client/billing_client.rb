require_relative 'http_client'

module JwtAuthClient
  # A high-level, service-specific client that inherits from HttpClient
  # and automatically sets the target_service to :billing_api.
  class BillingClient < HttpClient
    # The public entry point, mirroring the service object pattern,
    # but hardcoding the target_service.
    def self.call(user_id:, scopes: [], base_url: nil)
      super(user_id: user_id, target_service: :billing_api, scopes: scopes, base_url: base_url)
    end
  end
end
