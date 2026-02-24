require "./list"
require "./create"
require "./show"
require "./delete"
require "./extract"
require "./update"

module Command
  module Media
    class Root < Base
      description "Manage medias within this UPD"
      sub_command "list", List
      sub_command "create", Create
      sub_command "show", Show
      sub_command "delete", Delete
      sub_command "extract", Extract
      sub_command "update", Update

      def run_impl
        print_help
      end
    end
  end
end
