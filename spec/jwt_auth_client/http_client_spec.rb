# frozen_string_literal: true

require "spec_helper"

RSpec.describe JwtAuthClient::HttpClient do
  let(:user_id) { "user-abc-123" }
  let(:target_service) { :billing_api }
  let(:scopes) { ["read:user_data", "write:billing"] }
  let(:base_url) { "http://billing.local" }
  let(:client) { described_class.call(user_id: user_id, target_service: target_service, scopes: scopes) }

  # Captures the decoded JWT payload of every request made to +url+.
  def stub_and_capture_tokens(url, status: 200, body: { status: "ok" })
    payloads = []
    stub_request(:get, url).with do |request|
      token = request.headers["Authorization"].to_s.delete_prefix("Bearer ")
      payloads << JWT.decode(token, TEST_SECRET, true, algorithm: "HS256")[0]
      true
    end.to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
    payloads
  end

  describe ".call" do
    it "returns a Faraday connection pointed at the configured service URL" do
      expect(client).to be_a(Faraday::Connection)
      expect(client.url_prefix.to_s).to eq("#{base_url}/")
    end

    it "prefers the base_url override without changing the audience" do
      payloads = stub_and_capture_tokens("http://override.test/ping")
      described_class.call(user_id: user_id, target_service: target_service, base_url: "http://override.test").get("/ping")

      expect(payloads.first["aud"]).to eq("billing_api")
      expect(a_request(:get, "#{base_url}/ping")).not_to have_been_made
    end

    it "rejects a blank user_id or target_service" do
      expect { described_class.call(user_id: nil, target_service: target_service) }.to raise_error(ArgumentError, /user_id/)
      expect { described_class.call(user_id: user_id, target_service: "") }.to raise_error(ArgumentError, /target_service/)
    end

    it "raises UnknownServiceError when the service has no URL and no override" do
      JwtAuthClient.configuration.service_urls = {}
      expect { client }.to raise_error(JwtAuthClient::UnknownServiceError, /'billing_api' is not configured/)
    end

    it "raises ConfigurationError before building the connection when config is invalid" do
      JwtAuthClient.configuration.shared_secret = nil
      expect { client }.to raise_error(JwtAuthClient::ConfigurationError)
    end

    it "yields the connection so callers can add middleware" do
      seen = nil
      conn = described_class.call(user_id: user_id, target_service: target_service) { |c| seen = c }
      expect(seen).to equal(conn)
    end
  end

  describe "authorization header" do
    it "sends a Bearer JWT with the expected claims" do
      Timecop.freeze
      payloads = stub_and_capture_tokens("#{base_url}/v1/data")
      client.get("/v1/data")

      payload = payloads.first
      expect(payload["sub"]).to eq(user_id)
      expect(payload["iss"]).to eq("main_app_sso")
      expect(payload["aud"]).to eq("billing_api")
      expect(payload["scopes"]).to match_array(scopes)
      expect(payload["iat"]).to eq(Time.now.to_i)
      expect(payload["exp"]).to eq(Time.now.to_i + 300)
    end

    it "issues a fresh token (new jti) per request by default" do
      payloads = stub_and_capture_tokens("#{base_url}/v1/data")
      2.times { client.get("/v1/data") }

      expect(payloads.map { |p| p["jti"] }.uniq.size).to eq(2)
    end

    it "never sends an expired token from a long-lived connection" do
      Timecop.freeze(Time.at(1_700_000_000))
      payloads = stub_and_capture_tokens("#{base_url}/v1/data")
      client.get("/v1/data")

      Timecop.freeze(Time.at(1_700_000_000 + 301))
      client.get("/v1/data")

      expect(payloads.last["iat"]).to eq(1_700_000_000 + 301)
      expect(payloads.last["exp"]).to be > Time.now.to_i
    end

    context "with token reuse enabled" do
      before { JwtAuthClient.configuration.token_reuse_seconds = 60 }

      it "reuses the token within the reuse window" do
        Timecop.freeze(Time.at(1_700_000_000))
        payloads = stub_and_capture_tokens("#{base_url}/v1/data")
        client.get("/v1/data")
        Timecop.freeze(Time.at(1_700_000_000 + 59))
        client.get("/v1/data")

        expect(payloads.map { |p| p["jti"] }.uniq.size).to eq(1)
      end

      it "re-issues once the reuse window has elapsed" do
        Timecop.freeze(Time.at(1_700_000_000))
        payloads = stub_and_capture_tokens("#{base_url}/v1/data")
        client.get("/v1/data")
        Timecop.freeze(Time.at(1_700_000_000 + 60))
        client.get("/v1/data")

        expect(payloads.map { |p| p["jti"] }.uniq.size).to eq(2)
      end

      it "re-issues when the token is within the refresh margin of expiry" do
        JwtAuthClient.configuration.token_reuse_seconds = 10_000
        Timecop.freeze(Time.at(1_700_000_000))
        payloads = stub_and_capture_tokens("#{base_url}/v1/data")
        client.get("/v1/data")
        Timecop.freeze(Time.at(1_700_000_000 + 300 - described_class::REFRESH_MARGIN_SECONDS))
        client.get("/v1/data")

        expect(payloads.map { |p| p["jti"] }.uniq.size).to eq(2)
      end
    end
  end

  describe "middleware" do
    it "encodes request bodies and decodes JSON responses" do
      stub_request(:post, "#{base_url}/v1/items")
        .with(body: { name: "x" }.to_json, headers: { "Content-Type" => "application/json" })
        .to_return(status: 201, body: { id: 1 }.to_json, headers: { "Content-Type" => "application/json; charset=utf-8" })

      response = client.post("/v1/items", { name: "x" })
      expect(response.body).to eq("id" => 1)
    end

    it "raises Faraday errors on 4xx/5xx with the parsed JSON body attached" do
      stub_request(:get, "#{base_url}/v1/data")
        .to_return(status: 422, body: { error: "nope" }.to_json, headers: { "Content-Type" => "application/json" })

      expect { client.get("/v1/data") }.to raise_error(Faraday::UnprocessableEntityError) do |e|
        expect(e.response[:body]).to eq("error" => "nope")
      end
    end

    it "applies the configured timeouts" do
      JwtAuthClient.configure do |c|
        c.open_timeout = 1
        c.read_timeout = 7
        c.write_timeout = 3
      end

      expect(client.options.open_timeout).to eq(1)
      expect(client.options.read_timeout).to eq(7)
      expect(client.options.write_timeout).to eq(3)
      expect(client.options.timeout).to eq(7)
    end

    it "does not retry by default" do
      stub = stub_request(:get, "#{base_url}/v1/data").to_return(status: 503)
      expect { client.get("/v1/data") }.to raise_error(Faraday::ServerError)
      expect(stub).to have_been_requested.once
    end

    it "retries when retry_options is configured" do
      JwtAuthClient.configuration.retry_options = { max: 2, interval: 0, retry_statuses: [503] }
      stub = stub_request(:get, "#{base_url}/v1/data")
             .to_return({ status: 503 }, { status: 503 }, { status: 200, body: "{}", headers: { "Content-Type" => "application/json" } })

      expect(client.get("/v1/data").status).to eq(200)
      expect(stub).to have_been_requested.times(3)
    end
  end
end
