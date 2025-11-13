require "./list"

module Command
  module Dataset
    class Root < Base
      description "Manage datasets within this UPD"
      sub_command "list", List

      def run_impl
        print_help
      end
    end
  end
end
