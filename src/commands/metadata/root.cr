require "./show"
require "./add"
require "./list"

module Commands
  module Metadata
    class Root < Admiral::Command
      register_sub_command show, Commands::Metadata::Show, description: "Show metadata value for a specific key"
      register_sub_command add, Commands::Metadata::Add, description: "Add or update metadata value for a specific key"
      register_sub_command list, Commands::Metadata::List, description: "List all metadata entries"

      define_help description: "Operations on metadata"

      def root
        parent.as(Commands::Root)
      end

      rescue_from(Exception) do |e|
        Log.fatal{ e.message }
        Log.fatal{ help }
        exit -1
      end

      def run
        Log.fatal{ help }
        exit -1
      end
    end
  end
end
