# Shared utilities used in many parts of the application.
module Utils
  # Convert path to array.  If empty, utilized the 'root' resource.
  def Utils.get_path(request)
    path = request.path.split('/').reject { |x| x.empty? }
    if path.empty?
      return ['root']
    end
    return path
  end

  # Get hash of query string.
  def Utils.parse_query_string(request)
    queries = request.query_string.split('&')
    output = {}
    queries.each do |i|
      k, v = i.split('=')
      output[k] = v
    end
    return output
  end

  # Get status from Integer or String.
  def Utils.convert_status(status)
    if status.is_a? Integer
      return Utils.status_codes.fetch(status)
    elsif status.is_a? String
      return Utils.status_codes.find_index(status)
    else
      return Utils.status_codes.fetch(0)
    end
  end

  # Supported report statuses
  def Utils.status_codes
    return [
      'unknown',
      'unchanged',
      'changed',
      'pending',
      'failed'
    ]
  end

  # Filter based on regex for search box.
  def Utils.filter_response(response, query)
    filter = query.fetch('filter', nil)
    key = query.fetch('key', nil)
    if filter
      filter = URI.unescape(filter)
      response.delete_if do |i|
        i.fetch(key, 'host') !~ /#{filter}/
      end
    else
      return response
    end
  end

  # PuppetDashboard manually rewrote the report status to "pending" if a noop was detected.  This function detects it but does not rewrite.
  # https://github.com/sodabrew/puppet-dashboard/blob/35d40146f9b0e9d336df20f1820bd55227b4185d/app/models/report.rb#L215
  def Utils.is_pending(report)
    if report['status'] != 'failed'  # If failed, this data will be absent.
      report['metrics']['events']['values'].each do |event|
        if event[0] == 'noop' and event[2] > 0
          return true
        end
      end
    end
    return false
  end
end
