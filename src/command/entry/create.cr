module Command
  module Entry
    class Create < Base
      description "Create an entry"
      option "id", "i", "id", required: false, type: :string
      option "dataset_id", "d", "dataset id", required: true, type: :string
      option "url", "u", "media_url", required: true, type: :string
      option "email", "@", "email", required: false, type: :string

      def run_impl
        root.with_db do |db|
          puts db.exec(
            "INSERT into entries values (?, ?, ?, ?)", # ?,...
            args: [
              option("id") || UUID.v7.to_s,
              option("dataset_id"),
              option("url"),
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
