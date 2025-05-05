require "./list"

module Commands
  module Dataset
    class Root < Admiral::Command
      define_help description: "Operations on datasets"

      register_sub_command list, Commands::Dataset::List, description: "List the datasets"

      # register_sub_command show: Commands::Dataset::Show
      def root
        parent.as(Commands::Root)
      end

      rescue_from(Exception) do |e|
        Log.fatal { "#{e.message}\n" }
        Log.fatal { help }
        exit -1
      end

      def run
        Log.fatal { help }
        exit -1
      end
    end
  end
end