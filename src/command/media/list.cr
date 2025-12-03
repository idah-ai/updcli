require "json"
module Command
  module Media
    class List < Base
      description "List the Medias"

      def run_impl
        medias = root.database.query_all("SELECT id, media_type FROM medias") do |media|
          {
            id: media.read(String),
            media_type: media.read(String)
          }.to_h
        end
        if medias.empty?
          puts "No Medias found."
        else
          medias.each do |media|
            puts media.to_json
          end
        end
      end
    end
  end
end
