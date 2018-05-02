require './app/request'
require './app/controllers'

# Routing class.  Abstracts routing and translates function calls from the URI.
class Routes < Request

  def initialize(request, config)
    parse_request(request)
    set_configuration(config)
  end

  def root
    return Controllers::Tabular.new.root
  end

  def unchanged
    return Controllers::Tabular.new.unchanged
  end

  def changed
    return Controllers::Tabular.new.changed
  end

  def pending
    return Controllers::Tabular.new.pending
  end

  def failed
    return Controllers::Tabular.new.failed
  end

  def unresponsive
    return Controllers::Tabular.new.unresponsive
  end

  def upload
    return Controllers::Upload.new.upload
  end

  def host
    return Controllers::Tabular.new.host
  end

  def report
    return Controllers::Report.new.report
  end

end
