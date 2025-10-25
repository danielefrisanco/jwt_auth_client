require 'spec_helper'

RSpec.describe JwtAuthClient::BillingClient do
  let(:user_id) { 'test-user-456' }
  let(:scopes) { ['manage:invoices'] }
  let(:base_url) { 'http://billing.local' }
  let(:mock_connection) { instance_double(Faraday::Connection) }

  # Stub the call method on the parent HttpClient class
  before do
    allow(JwtAuthClient::HttpClient).to receive(:call).and_return(mock_connection)
  end

  # Test that the BillingClient delegates the call correctly to HttpClient,
  # ensuring that the target_service is hardcoded to :billing_api
  it 'delegates the call to HttpClient with the correct target_service' do
    # When BillingClient.call is invoked
    described_class.call(user_id: user_id, scopes: scopes)

    # It should have called the parent HttpClient with :billing_api
    expect(JwtAuthClient::HttpClient).to have_received(:call).with(
      user_id: user_id,
      target_service: :billing_api, # This is the key check
      scopes: scopes,
      base_url: nil
    )
  end

  it 'correctly passes an optional base_url override' do
    override_url = 'http://test.override'
    described_class.call(user_id: user_id, scopes: scopes, base_url: override_url)

    expect(JwtAuthClient::HttpClient).to have_received(:call).with(
      user_id: user_id,
      target_service: :billing_api,
      scopes: scopes,
      base_url: override_url # Ensure the override is passed
    )
  end
end
