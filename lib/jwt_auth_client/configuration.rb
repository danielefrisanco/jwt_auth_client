# frozen_string_literal: true

require_relative "errors"

module JwtAuthClient
  class Configuration
    # Only HMAC algorithms are supported until asymmetric signing lands.
    # "none" is deliberately absent: it produces unsigned tokens.
    SUPPORTED_ALGORITHMS = %w[HS256 HS384 HS512].freeze

    # RFC 7518 §3.2: an HMAC key must be at least as long as the hash output.
    MIN_SECRET_BYTES = { "HS256" => 32, "HS384" => 48, "HS512" => 64 }.freeze

    # The cryptographic key shared with the verifying services. Required.
    # Defaults to ENV["JWT_SERVICE_SECRET"]; there is intentionally no literal fallback.
    attr_accessor :shared_secret

    # The signing algorithm; one of SUPPORTED_ALGORITHMS.
    attr_accessor :algorithm

    # Token validity period in seconds.
    attr_accessor :default_expiry_seconds

    # The `iss` claim identifying the issuing application. Required.
    attr_accessor :issuer

    # Mapping of target service names (Symbol) to base URLs (String).
    attr_accessor :service_urls

    # HTTP timeouts (seconds) applied to every HttpClient connection.
    attr_accessor :open_timeout, :read_timeout, :write_timeout

    # How long (seconds) an HttpClient may reuse a token before issuing a new
    # one. 0 (default) issues a fresh token — and a fresh `jti` — per request,
    # which is best for replay detection on the verifier side. Raise it on hot
    # paths to skip the per-request signature. Tokens are always re-issued
    # within HttpClient::REFRESH_MARGIN_SECONDS of expiry regardless.
    attr_accessor :token_reuse_seconds

    # Options for Faraday's :retry middleware (requires the faraday-retry gem),
    # e.g. { max: 2, interval: 0.1, backoff_factor: 2 }. nil disables retries.
    attr_accessor :retry_options

    def initialize
      @shared_secret = ENV.fetch("JWT_SERVICE_SECRET", nil)
      @algorithm = "HS256"
      @default_expiry_seconds = 300
      @issuer = nil
      @service_urls = {}
      @open_timeout = 2
      @read_timeout = 5
      @write_timeout = 5
      @token_reuse_seconds = 0
      @retry_options = nil
    end

    # Retrieves the base URL for a given target service.
    #
    # @param target_service [Symbol, String]
    # @return [String]
    # @raise [UnknownServiceError] if the service is not configured.
    def base_url_for(target_service)
      key = target_service.to_s
      raise UnknownServiceError, "target_service must not be blank" if key.empty?

      service_urls[key.to_sym] or
        raise UnknownServiceError,
              "Base URL for service '#{key}' is not configured in JwtAuthClient.configuration.service_urls."
    end

    # Validates the configuration, raising on the first problem found.
    #
    # @return [self]
    # @raise [ConfigurationError]
    def validate!
      validate_algorithm!
      validate_shared_secret!
      validate_issuer!
      validate_expiry!
      validate_service_urls!
      validate_http_options!
      self
    end

    private

    def validate_algorithm!
      return if SUPPORTED_ALGORITHMS.include?(algorithm)

      raise ConfigurationError,
            "algorithm must be one of #{SUPPORTED_ALGORITHMS.join(', ')} (got #{algorithm.inspect})"
    end

    def validate_shared_secret!
      unless shared_secret.is_a?(String) && !shared_secret.empty?
        raise ConfigurationError,
              "shared_secret is required (set JwtAuthClient.configuration.shared_secret or JWT_SERVICE_SECRET)"
      end

      min = MIN_SECRET_BYTES.fetch(algorithm)
      return if shared_secret.bytesize >= min

      raise ConfigurationError,
            "shared_secret must be at least #{min} bytes for #{algorithm} (got #{shared_secret.bytesize})"
    end

    def validate_issuer!
      return if issuer.is_a?(String) && !issuer.empty?

      raise ConfigurationError, "issuer is required"
    end

    def validate_expiry!
      return if default_expiry_seconds.is_a?(Integer) && default_expiry_seconds.positive?

      raise ConfigurationError, "default_expiry_seconds must be a positive Integer"
    end

    def validate_service_urls!
      return if service_urls.is_a?(Hash)

      raise ConfigurationError, "service_urls must be a Hash of service name => base URL"
    end

    def validate_http_options!
      { open_timeout: open_timeout, read_timeout: read_timeout, write_timeout: write_timeout }.each do |name, value|
        next if value.is_a?(Numeric) && value.positive?

        raise ConfigurationError, "#{name} must be a positive number of seconds"
      end

      unless token_reuse_seconds.is_a?(Integer) && token_reuse_seconds >= 0
        raise ConfigurationError, "token_reuse_seconds must be a non-negative Integer"
      end

      return if retry_options.nil? || retry_options.is_a?(Hash)

      raise ConfigurationError, "retry_options must be nil or a Hash"
    end
  end

  class << self
    # @return [Configuration] the global configuration.
    def configuration
      @configuration ||= Configuration.new
    end

    # Yields the global configuration and validates it afterwards, so
    # misconfiguration surfaces at boot rather than on the first request.
    #
    # @yieldparam config [Configuration]
    # @return [Configuration]
    # @raise [ConfigurationError]
    def configure
      yield(configuration)
      configuration.validate!
    end

    # Discards the global configuration. Intended for test suites.
    def reset_configuration!
      @configuration = nil
    end
  end
end
