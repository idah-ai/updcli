module Command
  module Annotation
    class Show < Base
      Log = ::Log.for("annotation.show")

      description "Show an annotation"

      option "id", "i", "id", required: true, type: :string

      def run_impl
        annotations = root.database.query_all(
          "SELECT id, entry_id, shape_type, shape_args, category, properties, metadata FROM annotations WHERE ID = ?", option("id")
        ) do |ann|
          {
            id:         ann.read(String),
            entry_id:   ann.read(String),
            shape_type: ann.read(String),
            shape_args: JSON.parse(ann.read(String)),
            category:   ann.read(String),
            properties: JSON.parse(ann.read(String)),
            metadata:   ann.read(String).try { |str| JSON.parse(str) }
          }
        end

        if annotations.empty?
          Log.warn { "No annotation found." }
        else
          annotations.each do |ann|
            Log.info { ann.to_json }
          end
        end
      end
    end
  end
end
