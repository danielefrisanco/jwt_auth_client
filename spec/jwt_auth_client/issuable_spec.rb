# frozen_string_literal: true

require "spec_helper"

RSpec.describe JwtAuthClient::Issuable do
  let(:user_class) do
    Struct.new(:id, :sso_id, :email) do
      include JwtAuthClient::Issuable

      def jwt_claims
        { user_id: sso_id, email: email }
      end
    end
  end
  let(:user) { user_class.new(42, "sso-uuid-1", "a@example.com") }

  def decode(token)
    JWT.decode(token, TEST_SECRET, true, algorithm: "HS256")[0]
  end

  before { Timecop.freeze(Time.now) }

  it "issues a signed token carrying the model's claims and the registered claims" do
    payload = decode(user.to_jwt)

    expect(payload["user_id"]).to eq("sso-uuid-1")
    expect(payload["email"]).to eq("a@example.com")
    expect(payload["sub"]).to eq("sso-uuid-1")
    expect(payload["iss"]).to eq("main_app_sso")
    expect(payload["iat"]).to eq(Time.now.to_i)
    expect(payload["nbf"]).to eq(Time.now.to_i)
    expect(payload["exp"]).to eq(Time.now.to_i + 300)
    expect(payload["jti"]).to be_a(String)
    expect(payload).not_to have_key("aud")
  end

  it "supports a per-call expiry, audience and scopes" do
    payload = decode(user.to_jwt(expiry_seconds: 60, target_service: :client_app, scopes: ["profile"]))

    expect(payload["exp"]).to eq(Time.now.to_i + 60)
    expect(payload["aud"]).to eq("client_app")
    expect(payload["scopes"]).to eq(["profile"])
  end

  it "falls back to #id for the subject when jwt_claims has no user_id" do
    klass = Struct.new(:id) do
      include JwtAuthClient::Issuable
      def jwt_claims = { role: "admin" }
    end

    expect(decode(klass.new(7).to_jwt)["sub"]).to eq(7)
  end

  it "lets the including class override jwt_subject" do
    klass = Struct.new(:id, :email) do
      include JwtAuthClient::Issuable
      def jwt_claims = { email: email }
      def jwt_subject = email
    end

    expect(decode(klass.new(1, "x@y.z").to_jwt)["sub"]).to eq("x@y.z")
  end

  it "does not let custom claims override registered claims" do
    klass = Struct.new(:id) do
      include JwtAuthClient::Issuable
      def jwt_claims = { iss: "evil", exp: 1, sub: "someone-else", user_id: "me" }
    end
    payload = decode(klass.new(1).to_jwt)

    expect(payload["iss"]).to eq("main_app_sso")
    expect(payload["exp"]).to eq(Time.now.to_i + 300)
    expect(payload["sub"]).to eq("me")
  end

  it "raises NotImplementedError when jwt_claims is not defined" do
    klass = Struct.new(:id) { include JwtAuthClient::Issuable }
    expect { klass.new(1).to_jwt }.to raise_error(NotImplementedError, /must define #jwt_claims/)
  end
end
