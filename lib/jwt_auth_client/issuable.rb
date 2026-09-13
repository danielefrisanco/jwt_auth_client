# frozen_string_literal: true

require_relative "token_issuer"

module JwtAuthClient
  # Mixin for objects (typically a User model) that can be turned into a JWT,
  # e.g. by an SSO hub handing a signed identity token to a client app.
  #
  #   class User < ApplicationRecord
  #     include JwtAuthClient::Issuable
  #
  #     def jwt_claims
  #       { user_id: sso_id, email: email }
  #     end
  #   end
  #
  #   user.to_jwt                      # => "eyJhbGciOi..."
  #   user.to_jwt(expiry_seconds: 60)
  #
  # The registered claims (iss, sub, iat, nbf, exp, jti) are always set by the
  # gem; `jwt_claims` cannot override them. `sub` comes from `jwt_subject`,
  # which defaults to `jwt_claims[:user_id]`, falling back to `id`.
  module Issuable
    # Custom claims to embed in the token. Override in the including class.
    #
    # @return [Hash]
    def jwt_claims
      raise NotImplementedError, "#{self.class} must define #jwt_claims returning a Hash of claims"
    end

    # The `sub` claim. Override to use a different identifier.
    #
    # @return [String, Integer]
    def jwt_subject
      claims = jwt_claims
      claims[:user_id] || claims["user_id"] || (respond_to?(:id) ? id : nil)
    end

    # @param expiry_seconds [Integer, nil] overrides the configured default expiry.
    # @param target_service [Symbol, String, nil] optional `aud` claim.
    # @param scopes [Array<String>] optional `scopes` claim.
    # @return [String] the signed JWT.
    def to_jwt(expiry_seconds: nil, target_service: nil, scopes: [])
      TokenIssuer.call(
        user_id: jwt_subject,
        target_service: target_service,
        scopes: scopes,
        claims: jwt_claims,
        expiry_seconds: expiry_seconds
      )
    end
  end
end
