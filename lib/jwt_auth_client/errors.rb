# frozen_string_literal: true

module JwtAuthClient
  # Base class for all errors raised by this gem.
  class Error < StandardError; end

  # Raised when the global configuration is missing or invalid.
  class ConfigurationError < Error; end

  # Raised when a target service has no base URL configured.
  class UnknownServiceError < ConfigurationError; end

  # Raised when a token cannot be issued (wraps errors from the jwt gem).
  class TokenError < Error; end
end
