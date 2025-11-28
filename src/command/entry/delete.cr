require "uuid"

module Command
  module Entry
    class Delete < Base
      description "delete"

      option "id", "i", "id", required: false, type: :string

      def run_impl
        root.with_db do |db|
          puts db.exec(
            "DELETE FROM entries WHERE id = ?",
            args: [
              option("id")
            ]
          )
        end
      end
    end
  end
end
