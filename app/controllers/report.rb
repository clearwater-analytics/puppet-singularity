require './app/utils'
require './app/request'
require './app/models/tabular'
require './app/models/header'
require './app/models/report'

# Report Controller.  Renders the report from the model.
module Controllers
  class Report < Request

    def gen_response_hash(response)
      return {
        'status_code' => 200,
        'counts' => Models::Header.new.get_count,
        'values' => response,
        'template' => 'tabular'
      }
    end

    def report
      if @@path.length == 2
        report, metadata = Models::Report.new.get_report(@@path.fetch(1).to_i)
        # Because "pending" isn't a real status, rewrite.
        if Utils.is_pending(report)
          report['status'] = 'pending'
        end
        return {
          'status_code' => 200,
          'counts' => Models::Header.new.get_count,
          'report' => report,
          'metadata' => metadata,
          'template' => 'report'
        }
      else
        return {
          'status_code' => 200,
          'counts' => Models::Header.new.get_count,
          'values' => Models::Tabular.new.tabular({}),
          'template' => 'tabular'
        }
      end
    end

  end
end
