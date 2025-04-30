module Commands
  module Batch
    class Base < Commands::base
      def run
        raise "TODO: Implement run method"
      end

      def parse_impl(parser : OptionParser)
      end
    end
  end
end
