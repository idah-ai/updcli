require "mime"

module Command
  module Media
    class Create < Base
      Log = ::Log.for("media.create")

      description "create"

      option "id", "i", "id", required: false, type: :string
      option "key", "k", "key", required: false, type: :string
      option "file", "f", "file path", required: true, type: :string
      option "mimetype", "m", "mimetype", required: false, type: :string
      option "metadata", "h", "metadata", required: false, type: :string

      def run_impl
        result = root.database.exec(
          "INSERT into medias values (?, ?, ?, ?, ?)", # ?,...
          args: [
          option("id") || [
            Digest::SHA1.hexdigest(
              File.basename(
                option("file") || "",
                File.extname(option("file") || "")
              )),
            File.extname(option("file") || ""),
          ].join,
          option("key") || "",
          File.read(option("file") || "").to_slice,                       # ...
          option("mimetype") || begin
            MIME.from_filename(option("file") || "")
          rescue
            "application/octet-stream"
          end,
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
