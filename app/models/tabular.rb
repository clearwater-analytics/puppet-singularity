require './app/request'

# Get tabular data.
module Models
  class Tabular < Request

    def tabular(filter)
      return @@db.get_tabular(filter)
    end

  end
end
