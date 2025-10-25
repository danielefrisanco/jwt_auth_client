require 'spec_helper'
require 'webmock/rspec'
require 'jwt'
require 'timecop'

# WebMock must be enabled before tests run
WebMock.enable!

RSpec.describe JwtAuthClient::HttpClient do
  let(:user_id) { 'user-abc-123' }
  let(:target_service) { :billing_api }
  let(:scopes) { ['read:user_data', 'write:billing'] }
  let(:secret) { 'super_secret_internal_key' }
  let(:base_url) { 'http://billing.local' }

  before do
    # Configure the client globally for the tests
    JwtAuthClient.configure do |config|
      config.shared_secret = secret
      config.algorithm = 'HS256'
      config.default_expiry_seconds = 300
      config.issuer = 'main_app_sso'
      config.service_urls = { billing_api: base_url }
    end
  end

  # Helper method to decode the JWT from the headers
  def decode_token_from_header(request_headers)
    # FIX: Header value might be a String or an Array depending on the environment/WebMock version.
    # We retrieve the actual string value.
    auth_header = request_headers['Authorization']
    token_string = auth_header.is_a?(Array) ? auth_header.first : auth_header
    
    token = token_string.split(' ').last
    # Note: We use the secret key and enable verification to ensure the token is valid
    JWT.decode(token, secret, true, algorithm: 'HS256')[0]
  rescue JWT::DecodeError
    nil
  end

  # A context block to ensure time-sensitive claims (iat, exp) are predictable
  context 'when making an authenticated request' do
    let(:stubbed_url) { 'http://billing.local/v1/data' }
    let(:current_time) { Time.now.to_i }

    before do
      Timecop.freeze(Time.at(current_time))

      # Stub the HTTP request to capture headers and prevent real network access
      stub_request(:get, stubbed_url)
        .with do |request|
          @request_headers = request.headers
          true
        end
        .to_return(status: 200, body: { status: 'ok' }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    after { Timecop.return }

    it 'successfully creates a Faraday connection object' do
      client = described_class.call(user_id: user_id, target_service: target_service, scopes: scopes)
      expect(client).to be_a(Faraday::Connection)
    end

    it 'makes a request using the configured base URL' do
      client = described_class.call(user_id: user_id, target_service: target_service, scopes: scopes)
      client.get('/v1/data')

      expect(WebMock).to have_requested(:get, stubbed_url)
    end
    
    it 'injects a Bearer Authorization header containing a JWT' do
      client = described_class.call(user_id: user_id, target_service: target_service, scopes: scopes)
      client.get('/v1/data')

      # FIX: Check for presence using standard matchers
      auth_header = @request_headers['Authorization']
      expect(auth_header).to be_a(String)
      expect(auth_header).not_to be_empty
      expect(auth_header).to start_with('Bearer ')
    end

    it 'uses the base_url override when provided' do
      override_url = 'http://override-api.test'
      client = described_class.call(user_id: user_id, target_service: target_service, scopes: scopes, base_url: override_url)
      
      # Stub the override URL
      stub_request(:get, "#{override_url}/test").to_return(status: 200)

      client.get('/test')
      
      expect(WebMock).to have_requested(:get, "#{override_url}/test")
      expect(WebMock).not_to have_requested(:get, "#{base_url}/test")
    end

    it 'generates a JWT containing the correct claims' do
      client = described_class.call(user_id: user_id, target_service: target_service, scopes: scopes)
      client.get('/v1/data')
      
      payload = decode_token_from_header(@request_headers)

      # Check standard claims
      expect(payload['sub']).to eq(user_id)
      expect(payload['iss']).to eq('main_app_sso')
      expect(payload['aud']).to eq(target_service.to_s)
      expect(payload['iat']).to eq(current_time)
      expect(payload['exp']).to eq(current_time + 300)
      expect(payload['jti']).to be_a(String)
      expect(payload['scopes']).to match_array(scopes)
    end
  end

  context 'when service URL is not configured' do
    before do
      # Temporarily clear service URLs for this context block
      @original_urls = JwtAuthClient.configuration.service_urls
      JwtAuthClient.configuration.service_urls = {} 
    end
    
    after do
      # Restore original service URLs
      JwtAuthClient.configuration.service_urls = @original_urls 
    end

    it 'raises an error when base_url is not provided and target_service is unknown' do
      expect { 
        described_class.call(user_id: user_id, target_service: target_service, scopes: scopes)
      }.to raise_error(ArgumentError, /Base URL for service 'billing_api' is not configured/)
    end
  end
end