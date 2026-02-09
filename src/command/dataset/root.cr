require "./list"
require "./show"
require "./delete"
require "./update"

module Command
  module Dataset
    class Root < Base
      description "Manage datasets within this UPD"
      sub_command "create", Create
      sub_command "delete", Delete
      sub_command "list", List
      sub_command "show", Show
      sub_command "update", Update

      def run_impl
        print_help
      end
    end
  end
end
