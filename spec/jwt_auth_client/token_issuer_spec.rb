require 'spec_helper'

RSpec.describe JwtAuthClient::TokenIssuer do
  let(:user_id) { 'user-abc-123' }
  let(:target_service) { 'billing_api' }
  let(:scopes) { ['read:user_data', 'write:billing'] }
  let(:secret) { 'super_secret_internal_key' }
  let(:algorithm) { 'HS256' }
  let(:expiry_seconds) { 300 }
  let(:issuer) { 'main_app_sso' }

  # Mock the global configuration for the tests
  before do
    allow(JwtAuthClient).to receive(:configuration).and_return(
      OpenStruct.new(
        shared_secret: secret,
        algorithm: algorithm,
        default_expiry_seconds: expiry_seconds,
        issuer: issuer
      )
    )
    # Freeze time to ensure 'iat' and 'exp' claims are predictable
    Timecop.freeze(Time.now)
  end
  
  # Ensure time is unfrozen after tests
  after do
    Timecop.return
  end
  
  # You will need to add the 'timecop' gem to your development dependencies
  # gem 'timecop', '~> 0.9', group: :development

  describe '.call' do
    let(:token) { described_class.call(user_id: user_id, target_service: target_service, scopes: scopes) }
    
    it 'returns a valid JWT string' do
      expect(token).to be_a(String)
      expect(token.split('.').size).to eq(3) # Header, Payload, Signature
    end

    context 'when decoding the generated token' do
      # Decode the token using the secret key and algorithm
      let(:decoded_token) do
        JWT.decode(token, secret, true, algorithm: algorithm)
      end
      
      let(:payload) { decoded_token[0] }
      let(:header) { decoded_token[1] }

      it 'uses the configured algorithm (HS256)' do
        expect(header['alg']).to eq(algorithm)
      end

      it 'includes all standard required claims (iss, sub, iat, exp, jti)' do
        # Check standard claims
        expect(payload['iss']).to eq(issuer)
        expect(payload['sub']).to eq(user_id)
        expect(payload).to have_key('iat')
        expect(payload).to have_key('exp')
        expect(payload).to have_key('jti')
      end
      
      it 'calculates the correct expiration time (exp)' do
        # Expiry should be exactly 'expiry_seconds' from now
        expected_exp = (Time.now + expiry_seconds.seconds).to_i
        expect(payload['exp']).to eq(expected_exp)
      end
      
      it 'includes the custom claims (aud and scopes)' do
        expect(payload['aud']).to eq(target_service)
        expect(payload['scopes']).to match_array(scopes)
      end
      
      it 'handles nil scopes and target_service without error' do
        token_no_scopes = described_class.call(user_id: user_id)
        decoded_no_scopes = JWT.decode(token_no_scopes, secret, true, algorithm: algorithm)
        payload_no_scopes = decoded_no_scopes[0]

        expect(payload_no_scopes).not_to have_key('aud')
        expect(payload_no_scopes).not_to have_key('scopes')
      end
    end
  end
end