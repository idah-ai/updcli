require "mime"

module Command
  module Media
    class Extract < Base
      # add option to show/list in place ?
      description "extract"

      option "id", "i", "id", required: true, type: :string
      option "key", "k", "key", required: false, type: :string
      option "output", "o", "output file", required: false, type: :string

      def run_impl
        root.with_db do |db|
          medias = db.query_all(
            "SELECT id, media_type, blob_data FROM medias WHERE id = ?",
            option("id")
          ) do |media|
            {
              id: media.read(String),
              media_type: media.read(String),
              blob: media.read(Slice(UInt8))
            }.to_h
          end
          if medias.empty?
            puts "No Medias found."
          else
            medias.each do |media|
              File.open(option("output") || media[:id].to_s, "w") do |file|
                file.write(media[:blob].to_slice)
              end
            end
          end
        end
      end
    end
  end
end
