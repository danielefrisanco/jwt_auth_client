# frozen_string_literal: true

require "spec_helper"

RSpec.describe JwtAuthClient::TokenIssuer do
  let(:user_id) { "user-abc-123" }
  let(:target_service) { "billing_api" }
  let(:scopes) { ["read:user_data", "write:billing"] }

  def decode(token, algorithm: "HS256")
    JWT.decode(token, TEST_SECRET, true, algorithm: algorithm)
  end

  before { Timecop.freeze(Time.now) }

  describe ".call" do
    let(:token) { described_class.call(user_id: user_id, target_service: target_service, scopes: scopes) }
    let(:payload) { decode(token)[0] }
    let(:header) { decode(token)[1] }

    it "returns a three-segment JWT string" do
      expect(token).to be_a(String)
      expect(token.split(".").size).to eq(3)
    end

    it "signs with the configured algorithm" do
      expect(header["alg"]).to eq("HS256")
    end

    it "includes iss, sub, iat, nbf, exp and a unique jti" do
      expect(payload["iss"]).to eq("main_app_sso")
      expect(payload["sub"]).to eq(user_id)
      expect(payload["iat"]).to eq(Time.now.to_i)
      expect(payload["nbf"]).to eq(Time.now.to_i)
      expect(payload["exp"]).to eq(Time.now.to_i + 300)
      expect(payload["jti"]).to match(/\A[0-9a-f-]{36}\z/)

      other = decode(described_class.call(user_id: user_id))[0]
      expect(other["jti"]).not_to eq(payload["jti"])
    end

    it "includes aud (as a string) and scopes" do
      expect(payload["aud"]).to eq("billing_api")
      expect(payload["scopes"]).to match_array(scopes)
    end

    it "stringifies a symbol target_service" do
      payload = decode(described_class.call(user_id: user_id, target_service: :billing_api))[0]
      expect(payload["aud"]).to eq("billing_api")
    end

    it "omits aud and scopes when not given" do
      payload = decode(described_class.call(user_id: user_id))[0]
      expect(payload).not_to have_key("aud")
      expect(payload).not_to have_key("scopes")
    end

    it "treats nil scopes and an empty target_service as absent" do
      payload = decode(described_class.call(user_id: user_id, target_service: "", scopes: nil))[0]
      expect(payload).not_to have_key("aud")
      expect(payload).not_to have_key("scopes")
    end

    it "wraps a single scope string in an array" do
      payload = decode(described_class.call(user_id: user_id, scopes: "read:all"))[0]
      expect(payload["scopes"]).to eq(["read:all"])
    end

    it "honours HS512" do
      JwtAuthClient.configuration.algorithm = "HS512"
      token = described_class.call(user_id: user_id)
      expect(decode(token, algorithm: "HS512")[1]["alg"]).to eq("HS512")
    end

    it "honours a per-call expiry_seconds" do
      payload = decode(described_class.call(user_id: user_id, expiry_seconds: 45))[0]
      expect(payload["exp"]).to eq(Time.now.to_i + 45)
    end

    it "rejects a non-positive expiry_seconds" do
      expect { described_class.call(user_id: user_id, expiry_seconds: 0) }.to raise_error(ArgumentError, /expiry_seconds/)
    end

    it "merges custom claims but never lets them override registered claims" do
      payload = decode(described_class.call(user_id: user_id, claims: { "email" => "a@b.c", iss: "evil", sub: "x" }))[0]
      expect(payload["email"]).to eq("a@b.c")
      expect(payload["iss"]).to eq("main_app_sso")
      expect(payload["sub"]).to eq(user_id)
    end

    it "rejects non-Hash claims" do
      expect { described_class.call(user_id: user_id, claims: []) }.to raise_error(ArgumentError, /claims must be a Hash/)
    end

    it "rejects a blank user_id" do
      expect { described_class.call(user_id: nil) }.to raise_error(ArgumentError, /user_id is required/)
      expect { described_class.call(user_id: "") }.to raise_error(ArgumentError, /user_id is required/)
    end

    it "raises ConfigurationError when the configuration is invalid at issue time" do
      JwtAuthClient.configuration.shared_secret = nil
      expect { described_class.call(user_id: user_id) }.to raise_error(JwtAuthClient::ConfigurationError)
    end

    it "wraps jwt gem failures in TokenError" do
      allow(JWT).to receive(:encode).and_raise(JWT::EncodeError, "boom")
      expect { described_class.call(user_id: user_id) }.to raise_error(JwtAuthClient::TokenError, /boom/)
    end
  end
end
