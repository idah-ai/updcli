require "duckdb"

module Command
  class Root < Base
    description "updcli: A command-line tool for managing Universal Portable Datasets (UPD)."
    option "input", "i",
      "Path to the input UPD file.",
      required: true,
      type: :string
    sub_command "init", Init

    property! database : DB::Connection

    def with_db
      db_file = option("input")

      DB.connect "duckdb://#{db_file}" do |database|
        yield database
      end
    end

    def run
      with_db do |db|
        @database = db
        super
      end
    end

    def run_impl
      print_help
    end
  end
end
