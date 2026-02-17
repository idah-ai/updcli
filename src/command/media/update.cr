require "mime"

module Command
  module Media
    class Update < Base
      description "Update a media"

      option "id", "i", "Media ID", required: true, type: :string
      option "key", "k", "Media key (required to identify the row)", required: true, type: :string
      option "file", "f", "New file path", required: false, type: :string
      option "mimetype", "m", "New MIME type", required: false, type: :string
      option "metadata", "h", "New metadata (JSON object)", required: false, type: :string

      def run_impl
        row = root.database.query_one?(
          "SELECT blob_data, media_type, metadata FROM medias WHERE id = ? AND key = ?",
          option("id"),
          option("key"),
          as: {Bytes?, String?, String}
        )

        raise Command::UpdError.new("Media '#{option("id")}' with key '#{option("key")}' not found", self) unless row

        current_blob, current_media_type, current_metadata = row

        new_blob, new_media_type = if (file_path = option("file"))
          raise Command::UpdError.new("File not found: #{file_path}", self) unless File.exists?(file_path)
          {
            File.read(file_path).to_slice,
            option("mimetype") || MIME.from_filename(file_path)
          }
        else
          {current_blob, option("mimetype") || current_media_type}
        end

        metadata_option = option("metadata")
        metadata = if metadata_option
          begin
            JSON.parse(metadata_option).as_h
          rescue ex : JSON::ParseException
            raise Command::UpdError.new("Invalid JSON in new metadata: #{ex.message}", self)
          end
        else
          begin
            JSON.parse(current_metadata).as_h
          rescue ex : JSON::ParseException
            raise Command::UpdError.new("Existing media metadata contains invalid JSON: #{ex.message}", self)
          end
        end

        metadata["Updated-At"] = JSON::Any.new(Time.local.to_s("%Y-%m-%d %H:%M:%S%:z"))
        metadata["Updated-By"] = JSON::Any.new("updcli")

        puts root.database.exec(
          "UPDATE medias SET blob_data = ?, media_type = ?, metadata = ? WHERE id = ? AND key = ?",
          args: [
            new_blob,
            new_media_type,
            metadata.to_json,
            option("id"),
            option("key")
          ]
        )
      end
    end
  end
end
