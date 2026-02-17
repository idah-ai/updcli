require "uuid"

module Command
  module Entry
    class Delete < Base
      Log = ::Log.for("entry:delete")

      description "delete"

      option "id", "i", "id", required: false, type: :string

      def run_impl
        result = root.database.exec(
          "DELETE FROM entries WHERE id = ?",
          args: [
            option("id")
          ]
        )

        Log.info {result}
      end
    end
  end
end
