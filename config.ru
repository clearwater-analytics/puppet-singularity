require 'rack'
require 'rack/static'
#require 'rack/request'
#require 'rack/response'
require './app/routes'

# The entry point for Passenger or WEBrick
def call(env, config)
  request = Rack::Request.new(env)
  response = Rack::Response.new

  begin
    response = Routes.new(request, config).call
  rescue => detail
    response.status = 500
    response['Content-Type'] = 'text/plain'
    response.write detail.message + "\n"
    response.write detail.backtrace.join("\n")
    response
  end
end

URI::DEFAULT_PARSER = URI::Parser.new(:UNRESERVED => URI::REGEXP::PATTERN::UNRESERVED + '|')  # Allow pipe chars in URI

# So that WEBrick can serve static assets.
use Rack::Static, urls: ['/public']

# Load configuration
begin
  config = YAML.load(File.open('/etc/puppet-singularity.yml', 'r').read)
rescue Exception
  puts 'Error loading config.  Using example config.'
  config = YAML.load(File.open('puppet-singularity.yml.example', 'r').read)
end

run Proc.new { |env| call(env, config) }
