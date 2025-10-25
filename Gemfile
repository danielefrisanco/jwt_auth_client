source "https://rubygems.org"
gemspec
group :development, :test do
  gem 'pry', '~> 0.14'

  # Core HTTP Client
  gem 'faraday', '~> 2.7' 
  
  # For conn.request :retry (now typically part of the faraday-excon or faraday-net_http gems)
  # gem 'faraday-retry' # You might need this explicitly if on an older version of Faraday 2+
  
  gem 'webmock', '~> 3.19' # For HTTP stubbing/testing
  gem 'timecop', '~> 0.9'  # For time-based testing
  # Testing tools
  gem 'rspec', '~> 3.0'

  # Faraday and required middleware
  # The core faraday gem is already included via gemspec
  # We must explicitly add the middleware that replaced faraday-middleware and faraday-json
  gem 'faraday-typhoeus' # A robust adapter
  gem 'faraday-retry', '~> 2.0' # Explicit gem for the :retry middleware
  
  # Note: JSON encoding/decoding middleware is often implicitly handled 
  # by faraday v2, or included in faraday-typhoeus or a different gem 
  # depending on the setup. Explicitly adding :json requests/responses
  # in the HttpClient often just needs the `json` gem itself.
end