module Command
  module Annotation
    class List < Base
      Log = ::Log.for("annotation.list")
      description "List the annotations"

      def run_impl
        annotations = root.database.query_all(
          "SELECT id, entry_id, shape_type, shape_args, category, properties, metadata FROM annotations;"
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
          Log.info { "No annotation found." }
        else
          annotations.each do |ann|
            Log.info { ann.to_json }
          end
        end
      end
    end
  end
end
