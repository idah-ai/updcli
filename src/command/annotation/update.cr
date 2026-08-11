module Command
  module Annotation
    class Update < Base
      Log = ::Log.for("annotation.update")

      description "Update an annotation"

      option "id", "i", "Annotation ID", required: true, type: :string
      option "type", "t", "New shape_type", required: false, type: :string
      option "shape", "s", "New shape_args (JSON)", required: false, type: :string
      option "category", "c", "New annotation category", required: false, type: :string
      option "properties", "p", "New annotation properties (JSON)", required: false, type: :string
      option "metadata", "h", "New metadata (JSON object)", required: false, type: :string

      def run_impl
        row = root.database.query_one?(
          "SELECT shape_type, shape_args, category, properties, metadata FROM annotations WHERE id = ?",
          option("id"),
          as: {String, String, String, String, String}
        )

        raise Command::UpdError.new("Annotation '#{option("id")}' not found", self) unless row

        current_type, current_shape, current_category, current_properties, current_metadata = row

        shape_args = if (shape_option = option("shape"))
          begin
            JSON.parse(shape_option).to_json
          rescue ex : JSON::ParseException
            raise Command::UpdError.new("Invalid JSON in new shape: #{ex.message}", self)
          end
        else
          current_shape
        end

        category_val = option("category") || current_category

        properties_val = if (properties_option = option("properties"))
          begin
            JSON.parse(properties_option).to_json
          rescue ex : JSON::ParseException
            raise Command::UpdError.new("Invalid JSON in new properties: #{ex.message}", self)
          end
        else
          current_properties
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
            raise Command::UpdError.new("Existing annotation metadata contains invalid JSON: #{ex.message}", self)
          end
        end

        metadata["Updated-At"] = JSON::Any.new(Time.local.to_s("%Y-%m-%d %H:%M:%S%:z"))
        metadata["Updated-By"] = JSON::Any.new("updcli")

        result = root.database.exec(
          "UPDATE annotations SET shape_type = ?, shape_args = ?, category = ?, properties = ?, metadata = ? WHERE id = ?",
          args: [
            option("type") || current_type,
            shape_args,
            category_val,
            properties_val,
            metadata.to_json,
            option("id")
          ]
        )

        Log.info { result }
      end
    end
  end
end
