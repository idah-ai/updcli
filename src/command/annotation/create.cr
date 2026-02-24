module Command
  module Annotation
    class Create < Base
      Log = ::Log.for("annotation.create")

      description "Create an entry"
      option "id", "i", "id", required: false, type: :string
      option "entry_id", "e", "entry id", required: true, type: :string
      option "type", "t", "shape_type", required: true, type: :string
      option "annotation", "a", "annotation value", required: true, type: :string
      option "shape", "s", "shape_args", required: true, type: :string
      option "metadata", "h", "metadata", required: false, type: :string

      def run_impl
        result = root.database.exec(
          "INSERT into annotations values (?, ?, ?, ?, ?, ?)", # ?,...
          args: [
          option("id") || UUID.v7.to_s,
          option("entry_id"),
          option("type"),
          JSON.parse(option("shape") || "").to_json,
          JSON.parse(option("annotation") || "").to_json,
          option("metadata") || {
            "Created-At": Time.local.to_s("%Y-%m-%d %H:%M:%S%:z"),
            "Updated-At": nil,
            "Created-by": "updcli",
          }.to_json,
        ]
        )
        Log.info { result }
      end
    end
  end
end
