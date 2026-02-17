require "uuid"

module Command
  module Dataset
    class Create < Base
      description "Create dataset"

      option "id", "i", "id", required: false, type: :string
      option "name", "n", "name", required: true, type: :string
      option "modality", "m", "modality", required: true, type: :string
      option "metadata", "h", "metadata (JSON object)", required: false, type: :string

      def run_impl
        # Build metadata starting from default '{}'
        metadata = {} of String => JSON::Any

        # Merge with user-provided metadata if any
        metadata_option = option("metadata") # Get the option value first
        if metadata_option
          begin
            metadata.merge!(JSON.parse(metadata_option).as_h)
          rescue ex : JSON::ParseException
            raise Command::UpdError.new("Invalid JSON metadata: #{ex.message}", self)
          end
        end

        metadata["Created-At"] = JSON::Any.new(Time.local.to_s("%Y-%m-%d %H:%M:%S%:z"))
        metadata["Updated-At"] = JSON::Any.new(nil)
        metadata["Created-by"] = JSON::Any.new("updcli")
        ret = root.database.exec(
          "INSERT into datasets (id, name, modality, metadata) values (?, ?, ?, ?)",
          args: [
            option("id") || UUID.v7.to_s,
            option("name"),
            option("modality"),
            metadata.to_json,
          ]
        )
        Log.info { ret }
      end
    end
  end
end
