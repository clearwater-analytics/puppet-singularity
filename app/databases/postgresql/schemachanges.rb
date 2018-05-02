require 'pg'

class SchemaNotUpToDate < StandardError
  def initialize(msg="Reached max retries.  Schema not up to date and did not update within the retry count.")
    super
  end
end

# PostgreSQL-specific schema changes utility.
# Maintains schema version table and attempts to run changeset when not in compliance.
class SchemaChanges
  def initialize(conn)
    @expectedversion = 2
    @db = conn
    @currentversion, @complete = get_schema_version
    wait_for_complete
    if @currentversion != @expectedversion
      update_schema
    end
  end

  def get_schema_version
    result = @db.exec('SELECT id, complete from schemaversion ORDER BY id DESC LIMIT 1')
    if result.ntuples == 0  # Initialize initial version
      result = @db.exec('INSERT INTO schemaversion (complete, comment) VALUES (TRUE, \'Initial Provisioning.\') RETURNING id, complete')
    end
    id = result.getvalue(0, 0).to_i
    if result.getvalue(0, 1) == 't' # Why can't pg return a real boolean?
      complete = true
    else
      complete = false
    end
    return id, complete
  end

  def update_schema
    next_version = @currentversion + 1
    @currentversion, @complete = self.send("schema_#{next_version}")
    if @currentversion != @expectedversion
      update_schema
    end
  end

  def wait_for_complete
    retries = 0
    until @complete do
      sleep(2)
      @currentversion, @complete = get_schema_version
      if retries >= 7  # Arbitrary retry count.
        raise SchemaNotUpToDate
        break
      end
      retries += 1
    end
  end

  def lock_schema(comment)
    params = [
      {:value => comment, :type => 0, :format => 0}
    ]
    @db.exec_params('INSERT INTO schemaversion (comment) VALUES ($1);', params)
  end

  def unlock_schema(version)
    params = [
      {:value => version, :type => 20, :format => 0}
    ]
    @db.exec_params('UPDATE schemaversion SET complete = TRUE where id = $1;', params)
  end

  # Schema update functions
  def schema_2
    lock_schema('Dropped archive column.')
    @db.exec('ALTER TABLE collections DROP COLUMN archived;')
    unlock_schema(2)
    return get_schema_version
  end

end
