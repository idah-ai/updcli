require "mime"

module Command
  module Media
    class Create < Base
      description "create"

      option "id", "i", "id", required: false, type: :string
      option "key", "k", "key", required: false, type: :string
      option "file", "f", "file path", required: true, type: :string
      option "email", "@", "email", required: false, type: :string

      def run_impl
        root.with_db do |db|
          puts db.exec(
            "INSERT into medias values (?, ?, ?, ?, ?)", # ?,...
            args: [
              option("id") || [
                Digest::SHA1.hexdigest(
                  File.basename(
                    option("file") || "",
                    File.extname(option("file")|| "")
                  )),
                File.extname(option("file")|| "")
              ].join,
              option("key") || "",
              File.read(option("file") || "").to_slice, # ...
              MIME.from_filename(option("file") || ""), #...
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
