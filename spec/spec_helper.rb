# Load the current directory into the load path
$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

# Load the main gem file
require 'jwt_auth_client' 

# Required for mocking configuration objects
require 'ostruct' 
# Required to decode the token for verification
require 'jwt' 

# Require Timecop for predictable time-based tests
require 'timecop' 
RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end