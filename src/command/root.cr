require "./init"
require "./append"
require "./dataset/root"
require "./entry/root"
require "./annotation/root"
require "./media/root"
require "./metadata/root"
require "./sign"
require "./verify"
require "./merge"

VERSION = {{ read_file("#{__DIR__}/../../VERSION").chomp }}

module Command
  class Root < Base
    description "updcli: A command-line tool for managing Universal Portable Datasets (UPD)."
    option "input", "i",
      "Path to the input UPD file.",
      type: :string
    option "version", "v",
      "Print version and exit.",
      type: :bool
    sub_command "annotation", Annotation::Root
    sub_command "append", Append
    sub_command "dataset", Dataset::Root
    sub_command "entry", Entry::Root
    sub_command "init", Init
    sub_command "media", Media::Root
    sub_command "merge", Merge
    sub_command "metadata", Metadata::Root
    sub_command "sign", Sign
    sub_command "verify", Verify

    property! database : DB::Connection

    def with_db(&)
      db_file = option("input")

      DB.connect "duckdb://#{db_file}" do |database|
        yield database
      end
    end

    def run
      if option("version") == "true"
        puts(VERSION)
        return
      end

      unless option("input")
        error!("Missing required option: --input <file>")
      end

      with_db do |database|
        @database = database
        super
      end
    end

    def run_impl
      print_help
    end
  end
end
