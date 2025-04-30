module Commands
  abstract class Base
    abstract def run
    abstract def parse_impl(parser : OptionParser)

    property command : String
    property description : String
    property usage : String

    def initialize(@command : String,
        @description : String = "",
        @usage : String = ""
      )
    end

    def parse(parser : OptionParser, callback : Base -> )
      parser.on(@command, @description) do
        parser.banner = "Usage: #{usage}"
        callback.call(self)
        parse_impl(parser)
      end
    end

    def arg_error(parser, message : String)
      STDERR.puts "ERROR: #{message}"
      STDERR.puts parser
      exit(1)
    end

  end
end
