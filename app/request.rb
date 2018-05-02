require 'logger'
require 'json'
require 'erb'

# Base request class.  This is the main core of the application.
class Request

  def parse_request(request)
    @@request = request
    @@path = Utils.get_path(request)
    @@query = Utils.parse_query_string(request)
  end

  def set_configuration(config)
    @@config = config
  end

  def initialize_db_connection
    require "./app/databases/#{@@config['db_type']}"
    @@db = Database::new(@@config)
  end

  def initialize_logger
    @@logging = Logger.new(@@config['log_file'])
  end

  # The call function from config.ru
  def call
    initialize_db_connection
    initialize_logger
    @response = self.send(@@path.fetch(0))
    @@db.close
    return format_response
  end

  # Format response based on Content-Type, both HTML and JSON are supported.
  def format_response
    status_code = @response['status_code'] ||= 500
    template = @response['template'] ||= 'upload'
    if @@request.media_type == 'application/json'
      headers = {'Content-Type' => 'application/json'}
      body = JSON.dump(@response)
    elsif @response['media_type'] == 'application/plain'
      headers = {'Content-Type' => 'text/html'}
      body = @response['message']
    else
      headers = {'Content-Type' => 'text/html'}
      body = File.read('./app/views/header.erb')
      body << File.read("./app/views/#{template}.erb")
      body << File.read('./app/views/footer.erb')
      body = ERB.new(body).result(binding)
    end
    output = []
    if body
      output << body
    end
    if output.empty?
      output << 'There was no response.'
    end
    [status_code, headers, output]
  end

end
