require 'pg'
require './app/utils'
require './app/databases/postgresql/schemachanges'

class NoCollectionException < StandardError
  def initialize(msg="No such collection exists.")
    super
  end
end

class NoHostException < StandardError
  def initialize(msg="No such host exists.")
    super
  end
end

class NoReportException < StandardError
  def initialize(msg="No such report exists.")
    super
  end
end

class UnrecoverableException < StandardError
  def initialize(msg="Fatal Database Error.")
    super
  end
end

# Database class for PostgreSQL.
class Database
  def initialize(config)
    @config = config
    @db = get_db_conn
    initialize_db_schema
    SchemaChanges::new(@db)
  end

  def get_db_conn
    return PG::Connection.new(
      {
        :host => @config['db_host'],
        :port => @config['db_port'],
        :dbname => @config['db_schema'],
        :user => @config['db_user'],
        :password => @config['db_password']
      }
    )
  end

  # Helper functions
  def exec_params(sql, params)
    @db.exec_params(sql, params)
  end

  def exec(sql)
    @db.exec(sql)
  end

  def close
    @db.close
  end

  def get_unresponsive
    sql = "
      SELECT count(n.host)
      FROM nodes n
      JOIN reports r on n.current_report = r.id
      where time < $1;
    "
    params = [
      {:value => Time.now - @config['unresponsive_detection_threshold']*60*60, :type => 0, :format => 0}
    ]
    return @db.exec_params(sql, params).getvalue(0, 0)
  end

  def get_count
    sql = "SELECT r.status, count(n.host)
      FROM nodes n
      JOIN reports r on n.current_report = r.id
      GROUP BY r.status;
    "
    output = {}
    Utils.status_codes.each { |code| output[code] = 0 }
    all = 0
    @db.exec(sql).values.each do |row|
      output[Utils.convert_status(row.fetch(0).to_i)] = row.fetch(1)
      all += row.fetch(1).to_i
    end
    output['all'] = all
    output['unresponsive'] = get_unresponsive
    return output
  end

  def get_tabular(filter)
    @fields = ['node_id', 'host', 'status', 'report_id', 'time', 'resources_changed', 'resources_failed', 'resources_total', 'runtime']
    if filter['host'] and filter['status']
      params = [
        {:value => filter['status'], :type => 20, :format => 0},
        {:value => filter['host'], :type => 20, :format => 0}
      ]
      sql = "SELECT n.id, n.host, r.status, r.id, r.time, r.resources_changed, r.resources_failed, r.resources_total, r.runtime
      FROM nodes n
      JOIN reports r on n.id = r.node_id
      WHERE r.status = $1 AND n.id = $2
      ORDER BY r.time desc;"
    elsif filter['host']
      params = [
        {:value => filter['host'], :type => 20, :format => 0}
      ]
      sql = "SELECT n.id, n.host, r.status, r.id, r.time, r.resources_changed, r.resources_failed, r.resources_total, r.runtime
      FROM nodes n
      JOIN reports r on n.id = r.node_id
      WHERE n.id = $1
      ORDER BY r.time desc;"
    elsif filter['status']
      params = [
        {:value => filter['status'], :type => 20, :format => 0}
      ]
      sql = "SELECT n.id, n.host, r.status, r.id, r.time, r.resources_changed, r.resources_failed, r.resources_total, r.runtime
      FROM nodes n
      JOIN reports r on n.current_report = r.id
      WHERE r.status = $1
      ORDER BY r.time desc;"
    elsif filter['unresponsive']
      params = [
        {:value => Time.now - @config['unresponsive_detection_threshold']*60*60, :type => 0, :format => 0}
      ]
      sql = "SELECT n.id, n.host, r.status, r.id, r.time, r.resources_changed, r.resources_failed, r.resources_total, r.runtime
        FROM nodes n
        JOIN reports r on n.current_report = r.id
        WHERE time < $1
        ORDER BY r.time DESC;"
    else
      params = []
      sql = "SELECT n.id, n.host, r.status, r.id, r.time, r.resources_changed, r.resources_failed, r.resources_total, r.runtime
      FROM nodes n
      JOIN reports r on n.current_report = r.id
      ORDER by r.time desc;"
    end
    result = @db.exec_params(sql, params)
    return format_values(result.values)
  end

  def fetch_report_metadata(report_id)
    params = [
      {:value => report_id, :type => 20, :format => 0}
    ]
    sql = 'SELECT r.file_handle, c.collection, r.node_id, d.report
           FROM reports r
           JOIN collections c ON r.collection = c.id
           JOIN reportdata d ON r.file_handle = d.id
           WHERE r.id = $1;'
    result = @db.exec_params(sql, params)
    return format_result(result)
  end

  def format_result(result)
    output = {}
    fields = result.fields
    row = result.values.fetch(0)
    fields.each_index do |i|
      if fields[i] == 'report' # dirty hack to force bytea parsing
        output[fields[i]] = @db.unescape_bytea(row.fetch(i))
      else
        output[fields[i]] = row.fetch(i)
      end
    end
    return output
  end

  def format_values(result)
    output = []
    result.each do |row|
      new_row = {}
      @fields.each_index do |i|
        if @fields[i] == 'status'
          new_row[@fields[i]] = Utils.convert_status(row[i].to_i)
        else
          new_row[@fields[i]] = row[i]
        end
      end
      output << new_row
    end
    return output
  end

  def initialize_timing_data_table
    @db.exec(
      'create table if not exists timing_data
        (
          report_id INTEGER NOT NULL,
          elapsed_time DOUBLE PRECISION NOT NULL,
          parse_timing DOUBLE PRECISION NOT NULL
        );'
    )
  end

  def store_timing_data(new_report_id, elapsed_time, parse_timing)
    params = [
      {:value => new_report_id, :type => 20, :format => 0},
      {:value => elapsed_time, :type => 0, :format => 0},
      {:value => parse_timing, :type => 0, :format => 0}
    ]
    @db.exec_params("INSERT INTO timing_data (report_id, elapsed_time, parse_timing) VALUES ($1, $2, $3)", params)
  end

  def get_collection_id(collection)
    params = [{:value => collection, :type => 0, :format => 0}]
    result = @db.exec_params('SELECT id from collections where collection = $1', params)
    if result.ntuples == 0
      raise NoCollectionException
    end
    return result.getvalue(0, 0).to_i
  end

  def insert_collection_id(collection)
    params = [{:value => collection, :type => 0, :format => 0}]
    result = @db.exec_params('INSERT INTO collections (collection) VALUES ($1) RETURNING id', params)
    return result.getvalue(0, 0).to_i
  end

  def get_previous_report(hostname)
    params = [{:value => hostname, :type => 0, :format => 0}]
    result = @db.exec_params(
      'SELECT n.id, n.current_report, r.status, r.collection, r.file_handle
        FROM nodes n
        JOIN reports r on n.id = r.node_id
        WHERE n.current_report = r.id and n.host = $1;',
      params
    )
    if result.ntuples == 0
      raise NoReportException
    elsif result.ntuples == 1
      return result.values[0].fetch(0).to_i, result.values[0].fetch(1).to_i, result.values[0].fetch(2).to_i, result.values[0].fetch(3).to_i, result.values[0].fetch(4).to_i
    else
      return result.values.fetch(0).to_i, nil, nil, nil, nil
    end
  end

  def get_host(hostname)
    params = [{:value => hostname, :type => 0, :format => 0}]
    result = @db.exec_params('SELECT id from nodes where host = $1', params)
    if result.ntuples == 0
      raise NoHostException
    elsif result.ntuples > 1
      raise UnrecoverableException
    else
      return result.getvalue(0, 0).to_i
    end
  end

  def insert_host(hostname)
    params = [{:value => hostname, :type => 0, :format => 0}]
    result = @db.exec_params('INSERT INTO nodes (host) VALUES ($1) RETURNING id', params)
    return result.getvalue(0, 0).to_i
  end

  def update_current_report(node_id, new_report_id)
      params = [
        {:value => new_report_id, :type => 20, :format => 0},
        {:value => node_id, :type => 20, :format => 0}
      ]
      @db.exec_params('UPDATE nodes SET current_report = $1 WHERE id = $2;', params)
  end

  def get_current_report_id(node_id, collection_id, current_report_status, time, changed, failed, total, runtime)
    params = [
      {:value => node_id, :type => 20, :format => 0},
      {:value => collection_id, :type => 0, :format => 0},
      {:value => current_report_status, :type => 20, :format => 0},
      {:value => time, :type => 0, :format => 0},
      {:value => changed, :type => 0, :format => 0},
      {:value => failed, :type => 0, :format => 0},
      {:value => total, :type => 0, :format => 0},
      {:value => runtime, :type => 0, :format => 0}
    ]
    result = @db.exec_params('INSERT INTO reports (node_id, collection, status, time, resources_changed, resources_failed, resources_total, runtime) VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id', params)
    return result.getvalue(0, 0)
  end

  def store_report_data(file_handle, report)
    params = [
      {:value => file_handle, :type => 0, :format => 0}
    ]
    result = @db.exec_params('SELECT id FROM reportdata WHERE id = $1', params)
    params = [
      {:value => @db.escape_bytea(report), :type => 0, :format => 0},
      {:value => file_handle, :type => 0, :format => 0}
    ]
    if result.ntuples == 1
      @db.exec_params('UPDATE reportdata SET report = $1 WHERE id = $2', params)
    else
      @db.exec_params('INSERT INTO reportdata (report, id) VALUES ($1, $2)', params)
    end
  end

  def store_report(new_report, file_handle, collection, new_report_id, report)
    store_report_data(file_handle, report)
    params = [
      {:value => new_report, :type => 0, :format => 0},
      {:value => file_handle, :type => 0, :format => 0},
      {:value => collection, :type => 20, :format => 0},
      {:value => new_report_id, :type => 20, :format => 0}
    ]
    @db.exec_params('UPDATE reports SET new_report = $1, file_handle = $2, collection = $3 where id = $4', params)
  end

  # This will run on every request, but if they exist it returns quickly.
  # Hopefully this helps get people up and running quickly.
  def initialize_db_schema
    @db.exec(
      'create table if not exists nodes
      (
        id SERIAL PRIMARY KEY,
        host VARCHAR(256) UNIQUE,
        last_seen TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        current_report INTEGER
      );

      create table if not exists collections
      (
        id SERIAL PRIMARY KEY,
        collection VARCHAR(256) NOT NULL,
        archived BOOL DEFAULT FALSE
      );

      create table if not exists reports
      (
        id SERIAL PRIMARY KEY,
        node_id INTEGER NOT NULL,
        file_handle INTEGER,
        status INTEGER NOT NULL,
        collection INTEGER NOT NULL,
        time TIMESTAMP NOT NULL,
        resources_changed INTEGER NOT NULL,
        resources_failed INTEGER NOT NULL,
        resources_total INTEGER NOT NULL,
        runtime REAL NOT NULL,
        new_report BOOL DEFAULT FALSE,
        FOREIGN KEY (node_id) REFERENCES nodes (id),
        FOREIGN KEY (collection) REFERENCES collections(id)
      );

      create table if not exists schemaversion
      (
        id SERIAL PRIMARY KEY,
        complete BOOL DEFAULT FALSE,
        comment VARCHAR(256) NOT NULL
      );
      create table if not exists reportdata
      (
        id SERIAL PRIMARY KEY,
        report bytea
      );
      '
    )
  end


end
