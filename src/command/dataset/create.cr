require "uuid"

module Command
  module Dataset
    class Create < Base
      description "create"

      option "id", "i", "id", required: false, type: :string
      option "name", "n", "name", required: true, type: :string
      option "modality", "m", "modality", required: true, type: :string
      option "metadata", "h", "metadata", required: false, type: :string

      def run_impl
        puts root.database.exec(
          "INSERT into datasets values (?, ?, ?, ?)", # ?,...
          args: [
            option("id") || UUID.v7.to_s,
            option("name"),
            option("modality"),
            option("metadata") || {
              "Created-At": Time.local.to_s("%Y-%m-%d %H:%M:%S%:z"),
              "Updated-At": nil,
              "Created-by": "updcli"
            }.to_json
          ]
        )
      end
    end
  end
end
