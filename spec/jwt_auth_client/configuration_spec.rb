# frozen_string_literal: true

require "spec_helper"

RSpec.describe JwtAuthClient::Configuration do
  subject(:config) { JwtAuthClient.configuration }

  describe "defaults" do
    before { JwtAuthClient.reset_configuration! }

    it "reads the secret from JWT_SERVICE_SECRET and has no literal fallback" do
      allow(ENV).to receive(:fetch).with("JWT_SERVICE_SECRET", nil).and_return(nil)
      expect(described_class.new.shared_secret).to be_nil

      allow(ENV).to receive(:fetch).with("JWT_SERVICE_SECRET", nil).and_return("from-env")
      expect(described_class.new.shared_secret).to eq("from-env")
    end

    it "defaults to HS256, 300s expiry, no issuer and no services" do
      fresh = described_class.new
      expect(fresh.algorithm).to eq("HS256")
      expect(fresh.default_expiry_seconds).to eq(300)
      expect(fresh.issuer).to be_nil
      expect(fresh.service_urls).to eq({})
    end
  end

  describe "#validate!" do
    it "passes for a valid configuration" do
      expect { config.validate! }.not_to raise_error
    end

    it "rejects a missing secret" do
      config.shared_secret = nil
      expect { config.validate! }.to raise_error(JwtAuthClient::ConfigurationError, /shared_secret is required/)
    end

    it "rejects an empty secret" do
      config.shared_secret = ""
      expect { config.validate! }.to raise_error(JwtAuthClient::ConfigurationError, /shared_secret is required/)
    end

    it "rejects a secret shorter than the hash output for the algorithm" do
      config.shared_secret = "too-short"
      expect { config.validate! }.to raise_error(JwtAuthClient::ConfigurationError, /at least 32 bytes for HS256/)

      config.algorithm = "HS512"
      config.shared_secret = "x" * 63
      expect { config.validate! }.to raise_error(JwtAuthClient::ConfigurationError, /at least 64 bytes for HS512/)
    end

    it "rejects the 'none' algorithm" do
      config.algorithm = "none"
      expect { config.validate! }.to raise_error(JwtAuthClient::ConfigurationError, /algorithm must be one of/)
    end

    it "rejects unsupported and asymmetric algorithms" do
      %w[RS256 ES256 hs256 foo].each do |alg|
        config.algorithm = alg
        expect { config.validate! }.to raise_error(JwtAuthClient::ConfigurationError)
      end
    end

    it "rejects a missing issuer" do
      config.issuer = nil
      expect { config.validate! }.to raise_error(JwtAuthClient::ConfigurationError, /issuer is required/)
    end

    it "rejects a non-positive expiry" do
      [0, -1, "300", nil].each do |value|
        config.default_expiry_seconds = value
        expect { config.validate! }.to raise_error(JwtAuthClient::ConfigurationError, /positive Integer/)
      end
    end
  end

  describe ".configure" do
    it "validates eagerly so misconfiguration fails at boot" do
      expect do
        JwtAuthClient.configure { |c| c.shared_secret = "short" }
      end.to raise_error(JwtAuthClient::ConfigurationError)
    end
  end

  describe "#base_url_for" do
    it "accepts symbols and strings" do
      expect(config.base_url_for(:billing_api)).to eq("http://billing.local")
      expect(config.base_url_for("billing_api")).to eq("http://billing.local")
    end

    it "raises UnknownServiceError for unknown or blank services" do
      expect { config.base_url_for(:nope) }.to raise_error(JwtAuthClient::UnknownServiceError, /'nope' is not configured/)
      expect { config.base_url_for(nil) }.to raise_error(JwtAuthClient::UnknownServiceError, /must not be blank/)
    end
  end

  describe ".reset_configuration!" do
    it "discards the current configuration" do
      config.issuer = "changed"
      JwtAuthClient.reset_configuration!
      expect(JwtAuthClient.configuration.issuer).to be_nil
    end
  end
end
