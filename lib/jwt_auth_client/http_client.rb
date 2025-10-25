require 'faraday'

module JwtAuthClient
  # HttpClient is a thin wrapper around Faraday that automatically issues a JWT
  # for the given user/scopes and injects it into the Authorization header
  # for secure inter-service communication.
  class HttpClient
    # The public entry point for making requests.
    #
    # @param user_id [String] The ID of the user to impersonate for this request.
    # @param target_service [String] The specific backend service the token is intended for (used for 'aud' claim).
    # @param scopes [Array<String>] The permissions required for the request.
    # @param base_url [String] The base URL of the service to call (overrides global config if provided).
    # @return [Faraday::Response] The response object from the HTTP request.
    def self.call(user_id:, target_service:, scopes: [], base_url: nil)
      new(user_id, target_service, scopes, base_url).connection
    end

    attr_reader :user_id, :target_service, :scopes, :base_url

    # Initializes the client instance.
    def initialize(user_id, target_service, scopes, base_url = nil)
      @user_id = user_id
      @target_service = target_service
      @scopes = scopes
      @base_url = base_url
      @config = JwtAuthClient.configuration
    end

    # Builds and memoizes the Faraday connection object.
    # The JWT is issued and included in a request header during this connection setup.
    #
    # @return [Faraday::Connection] The pre-configured Faraday connection.
    def connection
      @connection ||= Faraday.new(url: determined_base_url) do |conn|
        # Inject the Authorization header with the JWT before every request
        conn.request :authorization, 'Bearer', jwt_token 

        # Other standard middleware
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.response :raise_error # Raise exceptions on 4xx/5xx responses
        conn.adapter Faraday.default_adapter
      end
    end

    private

    # Determines the base URL, preferring the local override if provided.
    def determined_base_url
      base_url || @config.base_url_for(target_service)
    end

    # Uses the TokenIssuer service to generate the authenticated token.
    def jwt_token
      @jwt_token ||= TokenIssuer.call(
        user_id: user_id,
        target_service: target_service,
        scopes: scopes
      )
    end
  end
end
