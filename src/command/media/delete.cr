require "uuid"

module Command
  module Media
    class Delete < Base
      Log = ::Log.for("media.delete")
      description "delete"

      option "id", "i", "id", required: false, type: :string

      def run_impl
        result = root.database.exec(
          "DELETE FROM medias WHERE id = ?",
          args: [
            option("id"),
          ]
        )

        Log.info { result }
      end
    end
  end
end
