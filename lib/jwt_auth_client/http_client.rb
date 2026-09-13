# frozen_string_literal: true

require "faraday"
require_relative "errors"
require_relative "json_decoder"
require_relative "token_issuer"

module JwtAuthClient
  # A thin wrapper around Faraday that issues a JWT for the given user/scopes
  # and injects it as a Bearer token on every outgoing request.
  #
  # The returned connection is safe to keep and reuse for the lifetime of the
  # process: the token is (re)issued lazily per request, so a long-lived
  # connection never sends an expired token.
  class HttpClient
    # Tokens are re-issued when they are this close to expiring, even when
    # token reuse is enabled.
    REFRESH_MARGIN_SECONDS = 30

    # Builds an authenticated Faraday connection.
    #
    # @param user_id [String] the subject the token is issued for. Required.
    # @param target_service [Symbol, String] the audience; must be a key of
    #   `configuration.service_urls` unless `base_url` is given. Required.
    # @param scopes [Array<String>] permissions to embed in the token.
    # @param base_url [String, nil] overrides the configured URL for `target_service`
    #   (e.g. a canary host). It does not change the `aud` claim.
    # @yieldparam conn [Faraday::Connection] to add middleware (logging,
    #   instrumentation, ...) before the adapter is set.
    # @return [Faraday::Connection]
    def self.call(user_id:, target_service:, scopes: [], base_url: nil, &customize)
      new(user_id, target_service, scopes, base_url, &customize).connection
    end

    attr_reader :user_id, :target_service, :scopes, :base_url

    def initialize(user_id, target_service, scopes, base_url = nil, &customize)
      raise ArgumentError, "user_id is required" if user_id.nil? || user_id.to_s.empty?
      raise ArgumentError, "target_service is required" if target_service.nil? || target_service.to_s.empty?

      @user_id = user_id
      @target_service = target_service
      @scopes = Array(scopes)
      @base_url = base_url
      @customize = customize
      @config = JwtAuthClient.configuration
      @token_mutex = Mutex.new
    end

    # @return [Faraday::Connection] the memoised, pre-configured connection.
    def connection
      @connection ||= begin
        @config.validate!
        Faraday.new(url: determined_base_url) do |conn|
          configure_timeouts(conn)

          # Evaluated on every request, so the token is always fresh.
          conn.request :authorization, "Bearer", -> { bearer_token }
          conn.request :json

          # Response middleware runs innermost-first, so declaration order matters:
          #   raise_error  - outermost: raises on 4xx/5xx once retries are exhausted,
          #                  with the already-parsed JSON body attached to the error.
          #   retry        - (opt-in) sees raw statuses, so `retry_statuses` works.
          #   json         - innermost: parses the body before anything else sees it.
          conn.response :raise_error
          configure_retry(conn)
          conn.response :json, parser_options: { decoder: [JsonDecoder, :parse] }

          @customize&.call(conn)
          conn.adapter Faraday.default_adapter
        end
      end
    end

    # Returns a valid token, issuing a new one when there is none, when the
    # cached one is within REFRESH_MARGIN_SECONDS of expiry, or when
    # `configuration.token_reuse_seconds` has elapsed since it was issued.
    #
    # @return [String]
    def bearer_token
      @token_mutex.synchronize do
        issue_token! if token_stale?
        @token
      end
    end

    private

    def determined_base_url
      base_url || @config.base_url_for(target_service)
    end

    def configure_timeouts(conn)
      conn.options.open_timeout  = @config.open_timeout
      conn.options.read_timeout  = @config.read_timeout
      conn.options.write_timeout = @config.write_timeout
      conn.options.timeout       = @config.read_timeout # for adapters that only honour :timeout
    end

    def configure_retry(conn)
      return unless @config.retry_options

      begin
        require "faraday/retry"
      rescue LoadError
        raise ConfigurationError, "retry_options is set but the faraday-retry gem is not available"
      end
      conn.request :retry, **@config.retry_options
    end

    def token_stale?
      return true if @token.nil?

      now = Time.now.to_i
      now >= @token_expires_at - REFRESH_MARGIN_SECONDS ||
        now >= @token_issued_at + @config.token_reuse_seconds
    end

    def issue_token!
      @token_issued_at = Time.now.to_i
      @token_expires_at = @token_issued_at + @config.default_expiry_seconds
      @token = TokenIssuer.call(user_id: user_id, target_service: target_service, scopes: scopes)
    end
  end
end
