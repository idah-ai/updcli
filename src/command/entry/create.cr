module Command
  module Entry
    class Create < Base
      Log = ::Log.for("entry:create")

      description "Create an entry"
      option "id", "i", "id", required: false, type: :string
      option "dataset_id", "d", "dataset id", required: true, type: :string
      option "url", "u", "media_url", required: true, type: :string
      option "metadata", "h", "metadata", required: false, type: :string

      def run_impl
        result = root.database.exec(
          "INSERT into entries values (?, ?, ?, ?)", # ?,...
          args: [
          option("id") || UUID.v7.to_s,
          option("dataset_id"),
          option("url"),
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
