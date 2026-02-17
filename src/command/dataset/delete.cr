require "uuid"

module Command
  module Dataset
    class Delete < Base
      Log = ::Log.for("dataset:update")

      description "delete"

      option "id", "i", "id", required: false, type: :string

      def run_impl
        result = root.database.exec(
          "DELETE FROM datasets WHERE id = ?",
          args: [
            option("id"),
          ]
        )
        Log.info { result }
      end
    end
  end
end
