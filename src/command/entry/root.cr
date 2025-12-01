require "./list"
require "./show"
require "./delete"
require "./create"

module Command
  module Entry
    class Root < Base
      description "Manage entries within this UPD"
      sub_command "list", List
      sub_command "show", Show
      sub_command "delete", Delete
      sub_command "create", Create

      def run_impl
        print_help
      end
    end
  end
end
