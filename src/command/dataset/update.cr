require "uuid"

module Command
  module Dataset
    class Update < Base
      description "Update dataset"

      option "id", "i", "Dataset ID", required: true, type: :string
      option "name", "n", "New name", required: false, type: :string
      option "modality", "m", "New modality", required: false, type: :string
      option "metadata", "h", "New metadata (JSON object)", required: false, type: :string

      def run_impl
        # Get current dataset
        dataset = root.database.query_one?(
          "SELECT name, modality, metadata FROM datasets WHERE id = ?",
          option("id"),
          as: {String, String, String}
        )

        raise "Dataset '#{option("id")}' not found" unless dataset

        current_name, current_modality, current_metadata = dataset


        metadata_option = option("metadata")
        metadata = if metadata_option
          begin
            JSON.parse(metadata_option).as_h
          rescue ex : JSON::ParseException
            raise "Invalid JSON in new metadata: #{ex.message}"
          end
        else
          begin
            JSON.parse(current_metadata).as_h
          rescue ex : JSON::ParseException
            raise "Existing dataset metadata contains invalid JSON: #{ex.message}"
          end
        end

        metadata["Updated-At"] = JSON::Any.new(Time.local.to_s("%Y-%m-%d %H:%M:%S%:z"))
        metadata["Updated-By"] = JSON::Any.new("updcli")

        # Update database
        puts root.database.exec(
          "UPDATE datasets SET name = ?, modality = ?, metadata = ? WHERE id = ?",
          args: [
            option("name") || current_name,
            option("modality") || current_modality,
            metadata.to_json,
            option("id")
          ]
        )
      end
    end
  end
end