require './app/request'
require './app/utils'
require 'json'
require 'zlib'

# Report upload model.
module Models
  class Upload < Request

    # Begin.
    def upload
      begin
        @body = @@request.body.read
        @collection = "#{Date.today.year}-#{Date.today.month}-#{Date.today.day}"
        @collection_id = get_collection_id
        @current_report = parse_yaml(@body)
        # Because "pending" isn't a real status, rewrite.
        if Utils.is_pending(@current_report)
          @current_report['status'] = 'pending'
        end
        @@logging.info("Recieved report: #{@current_report['host']}")
        # TODO: 'pending' status shows itself as status: 'unchanged' but with special information in the execution log (ex. noop)
        # Fix should be to check the metrics key and detect if noop >= 1.  If so, rewrite status to "pending"
        # https://github.com/sodabrew/puppet-dashboard/blob/35d40146f9b0e9d336df20f1820bd55227b4185d/app/models/report.rb#L215
        # Apparently sodabrew dynamically generates report status based on analysis of resource_statuses and doesn't simply accept Puppet's status as law.
        @current_report_status = Utils.convert_status(@current_report['status'])
        process_report
      rescue Exception => e
        @@logging.error(e.message)
      end
    end

    def store_timing_data
      @@db.initialize_timing_data_table
      elapsed_time = Time.now - @begin_time
      @@logging.debug("Processing and storing report for node #{@node_id} took: #{elapsed_time} seconds.")
      @@db.store_timing_data(params)
    end

    def get_collection_id
      begin
        return @@db.get_collection_id(@collection)
      rescue
        @@logging.debug("Collection (#{@collection}) does not appear to exist.  Creating.")
        return @@db.insert_collection_id(@collection)
      end
    end

    def process_report
      @node_id, @previous_report_id, @previous_report_status, @previous_report_collection, @previous_file_handle = get_previous_report
      @new_report_id = get_current_report_id
      update_nodes
      store_report
    end

    # Does the host exist or do we need to make a new record?
    # Returns DB response.
    def get_previous_report
      begin
        result = @@db.get_previous_report(@current_report['host'])
      rescue NoReportException
        @@logging.debug("Could not get current report for node.  Checking if node (#{@current_report['host']}) exists.")
        begin
          result = @@db.get_host(@current_report['host'])
          @@logging.debug("Host found (#{result})")
        rescue NoHostException
          @@logging.debug("New host (#{@current_report['host']}) found.  Inserting.")
          result = @@db.insert_host(@current_report['host'])
        rescue UnrecoverableException
          @@logging.error("More than one result found where host = #{@current_report['host']}.  Cannot store report.")
          raise(msg)
        end
      end
      return result
    end

    # Change latest report to new report.
    def update_nodes
      @@db.update_current_report(@node_id, @new_report_id)
    end

    def get_current_report_id
      total, changed, failed, runtime = format_metrics(@current_report['metrics'])
      return @@db.get_current_report_id(@node_id, @collection_id, @current_report_status, @current_report['time'], changed, failed, total, runtime)
    end

    # Updates the header information.
    def format_metrics(metrics)
      if metrics == {}
        return 0, 0, 0, 0
      end
      output = {:total => 0, :failed => 0, :changed => 0, :total_time => 0}
      metrics['resources']['values'].each do |name, human_readable, count|
        if name == 'total'
          output[:total] += count
        elsif ['failed', 'failed_to_restart'].include? name
          output[:failed] += count
        elsif ['changed', 'restarted'].include? name
          output[:changed] += count
        else
          next
        end
      end
      metrics['time']['values'].each do |name, human_readable, count|
        if name == 'total'
          output[:total_time] += count
        end
      end
      return output[:total], output[:changed], output[:failed], output[:total_time]
    end

    # Determine whether or not this report is new.  Contains deduplication logic.
    def is_new_report
      if @previous_report_id.nil? # If there is no previous report.
        @@logging.info("Report not found: creating new. (Node: #{@node_id})")
        return true
      end
      if @current_report_status == Utils.convert_status('unchanged')  # Only dedupe unchanged status.
        if @current_report_status != @previous_report_status
          @@logging.debug("New Report: Current report status is different than previous report status. (Node: #{@node_id})")
          return true
        else
          @@logging.debug("Report found. Deduping. (Node: #{@node_id})")
          return false
        end
      else
        @@logging.debug("Status not \"unchanged\".  Skipping dedupe.  (Node: #{@node_id})")
        return true
      end
    end

    # Write report to database.
    def store_report
      new_report = is_new_report
      if new_report
        file_handle = @new_report_id
        collection = @collection_id
      else
        file_handle = @previous_file_handle
        collection = @previous_report_collection
      end
      begin
        gz = StringIO.new("")
        z = Zlib::GzipWriter.new(gz)
        z.write(@body)
      ensure
        z.close
      end
      report = gz.string
      @@logging.debug("Storing report. (New report id: #{@new_report_id})")
      @@db.store_report(new_report, file_handle, collection, @new_report_id, report)
    end

    # Strip the report down to just the bare minimum required to populate the database.
    # Parsing the entire YAML document can take up to 30 seconds, so we shortcut this by getting only what we care about at ingest time.
    # The parsing time is then passed on to the user when rendering.
    def parse_yaml(body)
      parse_begin_timing = Time.now  # Metrics gathering
      require "safe_yaml"
      output = ['---']  # Building up an array of what we need now.
      metric_block = false
      body.each_line do |line|
        if metric_block
          if line.start_with?('    ')
            output << line
            next
          else
            metric_block = false
          end
        end
        if line.start_with?('  metrics:')
          output << line
          metric_block = true
          next
        end
        if line.start_with?('  host: ') or line.start_with?('  time: ') or line.start_with?('  status: ')
          output << line
        end
      end
      parsed = YAML.load(output.join("\n"), :safe => :true, :deserialize_inputs => true)
      @parse_timing = Time.now - parse_begin_timing  # Metrics gathering
      return parsed
    end

  end
end
