require './app/utils'

# Generates header data.
module Models
  class Header < Request

    def get_count
      return @@db.get_count
    end

    def get_unresponsive
      return @@db.get_unresponsive
    end
  end
end
