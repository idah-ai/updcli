require "./list"
require "./show"
require "./delete"
require "./create"
require "./update"

module Command
  module Annotation
    class Root < Base
      description "Manage annotations within this UPD"
      sub_command "list", List
      sub_command "show", Show
      sub_command "delete", Delete
      sub_command "create", Create
      sub_command "update", Update

      def run_impl
        print_help
      end
    end
  end
end
