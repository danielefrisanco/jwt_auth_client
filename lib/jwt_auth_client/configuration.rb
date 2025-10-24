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

    def initialize
      @algorithm = 'HS256'
      @default_expiry_seconds = 300 
      @issuer = 'main_sso_app'
      @shared_secret = ENV['JWT_SERVICE_SECRET'] # Recommend reading from environment variable
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