module Command
  module Media
    class Show < Base
      description "Show a Media"
      option "id", "i", "id", required: true, type: :string

      def run_impl
        medias = root.database.query_all(
          "SELECT id, media_type FROM medias WHERE id = ?",
          option("id")
        ) do |media|
          {
            id: media.read(String),
            media_type: media.read(String)
          }
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
