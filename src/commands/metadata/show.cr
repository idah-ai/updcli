module Commands
  module Metadata
    class Show < Admiral::Command
      define_help description: "Show metadata value for a specific key"

      def root
        parent.as(Commands::Metadata::Root).root
      end

      def run
        if arguments.empty?
          Log.fatal{ "Error: Key is required" }
          Log.fatal{ help }
          exit -1
        end

        key = arguments[0]
        metadata = Data::Metadata.new(root.flags.filename)

        if value = metadata.get(key)
          Log.fatal{ value }
        else
          Log.fatal { "Error: Key '#{key}' not found" }
          exit -1
        end
      end
    end
  end
end
