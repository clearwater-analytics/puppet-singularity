require './app/utils'
require './app/request'
require './app/models/tabular'
require './app/models/header'

# Tabular controller.  Generates table view.
module Controllers
  class Tabular < Request

    def gen_response_hash(response, caller)
      return {
        'status_code' => 200,
        'counts' => Models::Header.new.get_count,
        'values' => Utils.filter_response(response, @@query),
        'template' => 'tabular',
        'caller' => caller
      }
    end

    def root
      filter = {}
      return gen_response_hash(Models::Tabular.new.tabular(filter), 'all')
    end

    def unchanged
      filter = {'status' => Utils.convert_status('unchanged')}
      return gen_response_hash(Models::Tabular.new.tabular(filter), 'unchanged')
    end

    def changed
      filter = {'status' => Utils.convert_status('changed')}
      return gen_response_hash(Models::Tabular.new.tabular(filter), 'changed')
    end

    def pending
      filter = {'status' => Utils.convert_status('pending')}
      return gen_response_hash(Models::Tabular.new.tabular(filter), 'pending')
    end

    def failed
      filter = {'status' => Utils.convert_status('failed')}
      return gen_response_hash(Models::Tabular.new.tabular(filter), 'failed')
    end

    def unresponsive
      filter = {'unresponsive' => true}
      return gen_response_hash(Models::Tabular.new.tabular(filter), 'unresponsive')
    end

    def host
      if @@path.length == 3
        filter = {'host' => @@path.fetch(1), 'status' => @@path.fetch(2)}
      elsif @@path.length == 2
        filter = {'host' => @@path.fetch(1)}
      else
        filter = {}
      end
      return gen_response_hash(Models::Tabular.new.tabular(filter), '')
    end
  end
end
