# frozen_string_literal: true

require "jwt"
require "securerandom"
require_relative "errors"

module JwtAuthClient
  # Issues short-lived, signed JWTs carrying the registered claims
  # (iss, sub, iat, nbf, exp, jti) plus the optional `aud`, `scopes` and any
  # caller-supplied custom claims.
  class TokenIssuer
    # Claims that are always set by the issuer and can never be overridden by
    # caller-supplied custom claims.
    REGISTERED_CLAIMS = %i[iss sub iat nbf exp jti].freeze

    # @param user_id [String] the subject (`sub`) of the token. Required.
    # @param target_service [Symbol, String, nil] the audience (`aud`).
    # @param scopes [Array<String>, nil] permissions granted by the token.
    # @param claims [Hash] extra custom claims (e.g. email); registered claims
    #   in this hash are ignored.
    # @param expiry_seconds [Integer, nil] overrides `configuration.default_expiry_seconds`.
    # @return [String] the signed JWT.
    def self.call(user_id:, target_service: nil, scopes: [], claims: {}, expiry_seconds: nil)
      new(user_id, target_service, scopes, claims: claims, expiry_seconds: expiry_seconds).issue
    end

    def initialize(user_id, target_service, scopes, claims: {}, expiry_seconds: nil)
      raise ArgumentError, "user_id is required" if user_id.nil? || user_id.to_s.empty?
      raise ArgumentError, "claims must be a Hash" unless claims.is_a?(Hash)
      unless expiry_seconds.nil? || (expiry_seconds.is_a?(Integer) && expiry_seconds.positive?)
        raise ArgumentError, "expiry_seconds must be a positive Integer"
      end

      @user_id = user_id
      @target_service = target_service
      @scopes = Array(scopes)
      @claims = claims
      @expiry_seconds = expiry_seconds
      @config = JwtAuthClient.configuration
    end

    # @return [String] the signed JWT.
    # @raise [ConfigurationError] if the configuration is invalid.
    # @raise [TokenError] if the jwt gem fails to sign the payload.
    def issue
      @config.validate!
      JWT.encode(build_payload, @config.shared_secret, @config.algorithm)
    rescue JWT::EncodeError, JWT::DecodeError => e
      # The jwt gem reports bad HMAC keys as DecodeError even on encode.
      raise TokenError, "Failed to sign token: #{e.message}"
    end

    private

    def build_payload
      issued_at = Time.now.to_i

      payload = @claims.transform_keys(&:to_sym).reject { |key, _| REGISTERED_CLAIMS.include?(key) }
      payload[:aud] = @target_service.to_s unless @target_service.nil? || @target_service.to_s.empty?
      payload[:scopes] = @scopes unless @scopes.empty?

      payload.merge!(
        iss: @config.issuer,
        sub: @user_id,
        iat: issued_at,
        nbf: issued_at,
        exp: issued_at + (@expiry_seconds || @config.default_expiry_seconds),
        jti: SecureRandom.uuid
      )
    end
  end
end
