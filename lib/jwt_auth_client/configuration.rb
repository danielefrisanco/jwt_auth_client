module JwtAuthClient
  class Configuration
    # The cryptographic key known to all internal services
    attr_accessor :shared_secret
    
    # The algorithm used for signing (e.g., 'HS256')
    attr_accessor :algorithm
    
    # Default token validity period in seconds (e.g., 300 seconds = 5 minutes)
    attr_accessor :default_expiry_seconds
    
    # The issuer of the token (conventionally the main application ID)
    attr_accessor :issuer

    # The mapping of target service names (Symbol) to their base URLs (String)
    attr_accessor :service_urls

    def initialize
      @algorithm = 'HS256'
      @default_expiry_seconds = 300 
      @issuer = 'main_sso_app'
      # Added a default value for local testing if ENV variable is missing
      @shared_secret = ENV['JWT_SERVICE_SECRET'] || 'development_secret' 
      @service_urls = {}
    end

    # Retrieves the base URL for a given target service.
    # The HttpClient relies on this method to determine where to send the request.
    #
    # @param target_service [Symbol, String] The name of the service (e.g., :billing_api).
    # @return [String] The base URL.
    # @raise [ArgumentError] If the service is not configured.
    def base_url_for(target_service)
      url = service_urls[target_service.to_sym]
      raise ArgumentError, "Base URL for service '#{target_service}' is not configured in JwtAuthClient.service_urls." unless url
      url
    end
  end

  # Class method to expose the configuration object and the configuration block
  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration)
  end
end
