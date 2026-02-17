require "uuid"

module Command
  module Annotation
    class Delete < Base
      Log = ::Log.for("annotation.delete")
      description "delete"

      option "id", "i", "id", required: false, type: :string

      def run_impl
        result = root.database.exec(
          "DELETE FROM annotations WHERE id = ?",
          args: [
            option("id"),
          ]
        )

        Log.info { result }
      end
    end
  end
end
