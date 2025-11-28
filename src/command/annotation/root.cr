require "./list"
require "./show"
require "./delete"

module Command
  module Annotation
    class Root < Base
      description "Manage annotations within this UPD"
      sub_command "list", List
      sub_command "show", Show
      sub_command "delete", Delete

      def run_impl
        print_help
      end
    end
  end
end
