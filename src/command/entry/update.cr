module Command
  module Entry
    class Update < Base
      ::Log.for("entry.update")

      description "Update an entry"

      option "id", "i", "Entry ID", required: true, type: :string
      option "url", "u", "New media_url", required: false, type: :string
      option "metadata", "h", "New metadata (JSON object)", required: false, type: :string

      def run_impl
        entry = root.database.query_one?(
          "SELECT media_url, metadata FROM entries WHERE id = ?",
          option("id"),
          as: {String, String}
        )

        raise Command::UpdError.new("Entry '#{option("id")}' not found", self) unless entry

        current_url, current_metadata = entry

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
            raise Command::UpdError.new("Existing entry metadata contains invalid JSON: #{ex.message}", self)
          end
        end

        metadata["Updated-At"] = JSON::Any.new(Time.local.to_s("%Y-%m-%d %H:%M:%S%:z"))
        metadata["Updated-By"] = JSON::Any.new("updcli")

        result = root.database.exec(
          "UPDATE entries SET media_url = ?, metadata = ? WHERE id = ?",
          args: [
            option("url") || current_url,
            metadata.to_json,
            option("id")
          ]
        )

        Log.info { result }
      end
    end
  end
end
