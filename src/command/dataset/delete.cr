require "uuid"

module Command
  module Dataset
    class Delete < Base
      description "delete"

      option "id", "i", "id", required: false, type: :string

      def run_impl
        root.with_db do |db|
          puts db.exec(
            "DELETE FROM datasets WHERE id = ?",
            args: [
              option("id")
            ]
          )
        end
      end
    end
  end
end
