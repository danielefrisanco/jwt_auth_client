# frozen_string_literal: true

# Example: a service-specific client that fixes the target_service so call
# sites don't repeat it. Copy this into your application (it is not part of
# the gem) and adapt the service name.
#
#   client = BillingClient.call(user_id: current_user.id, scopes: ["read:invoices"])
#   client.get("/v1/invoices/latest")
#
require "jwt_auth_client"

class BillingClient < JwtAuthClient::HttpClient
  def self.call(user_id:, scopes: [], base_url: nil, &customize)
    super(user_id: user_id, target_service: :billing_api, scopes: scopes, base_url: base_url, &customize)
  end
end
