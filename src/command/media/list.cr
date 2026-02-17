require "json"

module Command
  module Media
    class List < Base
      Log = ::Log.for("media:list")

      description "List the Medias"

      def run_impl
        medias = root.database.query_all("SELECT id, media_type FROM medias") do |media|
          {
            id:         media.read(String),
            media_type: media.read(String),
          }
        end
        if medias.empty?
          Log.info { "No Medias found." }
        else
          medias.each do |media|
            Log.info { media.to_json }
          end
        end
      end
    end
  end
end
