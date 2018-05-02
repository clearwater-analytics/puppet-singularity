require './app/request'
require 'safe_yaml'
require 'zlib'
require 'archive/tar/minitar'
require 'stringio'
include Archive::Tar

# Extract the report, parse it, and render it.
module Models
  class Report < Request

    def get_report(report_id)
      @report_id = report_id
      @metadata = fetch_report_metadata
      return get_report_content, @metadata
    end

    def get_report_content
      output = nil
      begin
        gz = StringIO.new(@metadata['report'])
        z = Zlib::GzipReader.new(gz)
        output = YAML.load(z.read, :safe => true, :deserialize_inputs => true)
      ensure
        z.close
      end
      return output
    end

    def extract_file_from_tar(reader, file_handle)
      temp = StringIO.new
      tar = Minitar::Input.open(reader)
      tar.each do |entry|
        stats = {
          :current  => 0,
          :currinc  => 0,
          :entry    => entry
        }
        entry_file_name = entry.full_name.split('/')[-1]
        if entry_file_name == file_handle
          loop do
            data = entry.read(4096)
            break unless data
            stats[:currinc] = temp.write(data)
            stats[:current] += stats[:currinc]
          end
        end
      end
      temp.seek(0)
      return temp
    end

    def fetch_report_metadata
      return @@db.fetch_report_metadata(@report_id)
    end

  end
end
