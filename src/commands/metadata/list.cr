module Commands
  module Metadata
    class List < Admiral::Command
      define_help description: "List all metadata entries"

      define_flag starts_with : String,
        description: "Filter entries that start with the given prefix",
        long: "starts-with",
        short: "s"

      define_flag format : String,
        description: "Output format (plain, json, yaml)",
        long: "format",
        short: "f",
        default: "plain"

      def root
        parent.as(Commands::Metadata::Root).root
      end

      def run
        metadata = Data::Metadata.new(root.flags.filename)
        entries = metadata.list

        # Apply filter if starts_with flag is provided
        if prefix = flags.starts_with
          entries = entries.select { |key, _| key.starts_with?(prefix) }
        end

        if entries.empty?
          Log.debug { "No metadata entries found" }
        else
          Log.debug { "Metadata entries:" }
          puts Format.format(flags.format, entries)
        end
      end
    end
  end
end
