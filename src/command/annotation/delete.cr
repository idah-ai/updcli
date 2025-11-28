require "uuid"

module Command
  module Annotation
    class Delete < Base
      description "delete"

      option "id", "i", "id", required: false, type: :string

      def run_impl
        root.with_db do |db|
          puts db.exec(
            "DELETE FROM annotations WHERE id = ?",
            args: [
              option("id")
            ]
          )
        end
      end
    end
  end
end
