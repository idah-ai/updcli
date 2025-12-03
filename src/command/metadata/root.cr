require "./show"

module Command
  module Metadata
    class Root < Base
      description "Manage Metadata within this UPD"
      sub_command "show", Show

      def run_impl
        print_help
      end
    end
  end
end
