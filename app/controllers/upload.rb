require './app/request'
require './app/models/upload'

# Upload controller.  This is where reports come into Singularity.
module Controllers
  class Upload < Request
    def upload
      if @@request.post?
        Models::Upload.new.upload
        return {'status_code' => 200, 'message' => 'OK', 'media_type' => 'application/plain'}
      else
        return {'status_code' => 500, 'message' => 'This endpoint only accepts data in post form.', 'media_type' => 'application/plain'}
      end
    end
  end
end
