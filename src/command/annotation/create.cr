module Command
  module Annotation
    class Create < Base
      description "Create an entry"
      option "id", "i", "id", required: false, type: :string
      option "entry_id", "e", "entry id", required: true, type: :string
      option "type", "t", "shape_type", required: true, type: :string
      option "annotation", "a", "annotation value", required: true, type: :string
      option "shape", "s", "shape_args", required: true, type: :string
      option "email", "@", "email", required: false, type: :string

      def run_impl
        root.with_db do |db|
          puts db.exec(
            "INSERT into annotations values (?, ?, ?, ?, ?, ?)", # ?,...
            args: [
              option("id") || UUID.v7.to_s,
              option("entry_id"),
              option("type"),
              JSON.parse(option("annotation") || "").to_json,
              JSON.parse(option("shape") || "").to_json,
              {
                "Created-At": Time.local.to_s("%Y-%m-%d %H:%M:%S%:z"),
                "Updated-At": nil,
                "Created-by": option("email") || "updcli"
              }.to_json
            ]
          )
        end
      end
    end
  end
end
