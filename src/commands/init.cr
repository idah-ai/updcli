require "./base"

module Commands
  class Init < Base
    INIT_SCHEMA = {{read_file("sql/schema.sql")}}

    property! filename : String

    def parse_impl(parser : OptionParser)
      parser.unknown_args do |args|
        if args.size == 1
          self.filename = args.first
        else
          arg_error(parser, "Invalid number of arguments. Expected 1, got #{args.size}.")
        end
      end
    end

    def initialize
      super(
        "init",
        description: "Initialize a new datset file",
        usage: "datset init <filename>"
      )
    end

    def run
      DB.open "sqlite3://./#{filename}" do |db|
        # Poor's man execution.
        INIT_SCHEMA.split(";").each do |stmt|
          stmt = stmt.strip
          next if stmt.empty?

          db.exec(stmt)
        end

        puts "Created datset file: #{filename}"
      end
    end
  end
end
