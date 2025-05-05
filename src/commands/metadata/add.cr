module Commands
  module Metadata
    class Add < Admiral::Command
      define_help description: "Add or update metadata value for a specific key"

      def root
        parent.as(Commands::Metadata::Root).root
      end

      def run
        if arguments.size < 2
          Log.fatal { "Error: Both key and value are required" }
          Log.fatal { help }
          exit -1
        end

        key = arguments[0]
        value = arguments[1]

        # Validate JSON if provided
        begin
          # Try to parse as JSON to validate, but we store the original string
          JSON.parse(value)
        rescue e : JSON::ParseException
          Log.fatal { "Error: Value is not valid JSON: #{e.message}" }
          exit -1
        end

        metadata = Data::Metadata.new(root.flags.filename)
        metadata.add(key, value)
        Log.debug { "Metadata '#{key}' added successfully" }
      end
    end
  end
end
