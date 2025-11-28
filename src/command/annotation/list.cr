module Command
  module Annotation
    class List < Base
      description "List the annotations"

      def run_impl
        root.with_db do |db|
          annotations = db.query_all(
            "SELECT id, shape_type, annotation, shape_args FROM annotations;"
          ) do |a|
            {
              id: a.read(String),
              shape_type: a.read(String),
              annotation: JSON.parse(a.read(String)),
              shape_args: JSON.parse(a.read(String))
            }
          end

          if annotations.empty?
            puts "No annotation found."
          else
            annotations.each do |a|
              puts a.to_json
            end
          end

        end
      end
    end
  end
end
