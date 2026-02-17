module Command
  module Annotation
    class Show < Base
      Log = ::Log.for("annotation:show")

      description "Show an annotation"

      option "id", "i", "id", required: true, type: :string
      def run_impl
        annotations = root.database.query_all(
          "SELECT id, shape_type, annotation, shape_args FROM annotations WHERE ID = ?", option("id")
        ) do |a|
          {
            id: a.read(String),
            shape_type: a.read(String),
            annotation: JSON.parse(a.read(String)),
            shape_args: JSON.parse(a.read(String))
          }
        end

        if annotations.empty?
          Log.warn {"No annotation found."}
        else
          annotations.each do |a|
            Log.info { a.to_json }
          end
        end
      end
    end
  end
end
