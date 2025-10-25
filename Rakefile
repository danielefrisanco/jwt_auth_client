require 'rake'
require 'rake/testtask'
require 'rspec/core/rake_task'
require 'rubygems/package_task'
require "bundler/gem_tasks"

# Load the gemspec to get gem metadata
spec = Gem::Specification.load("jwt_auth_client.gemspec")

# Task to run all RSpec tests
RSpec::Core::RakeTask.new(:spec) do |t|
  # Use RSpec's command-line options
  t.rspec_opts = "--color --format documentation"
  # Specify the files to run
  t.pattern = 'spec/**/*_spec.rb'
end

# Define 'test' as an alias for 'spec'
task :test => :spec

# Define a task for building the gem (creates the .gem file)
Gem::PackageTask.new(spec) do |pkg|
  # Optional: Customize the package task if necessary
end

# Default task is usually to run tests
task :default => :spec