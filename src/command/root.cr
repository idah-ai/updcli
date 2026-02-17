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

module Command
  class Root < Base
    description "updcli: A command-line tool for managing Universal Portable Datasets (UPD)."
    option "input", "i",
      "Path to the input UPD file.",
      required: true,
      type: :string
    sub_command "init", Init
    sub_command "append", Append
    sub_command "dataset", Dataset::Root
    sub_command "media", Media::Root
    sub_command "entry", Entry::Root
    sub_command "annotation", Annotation::Root
    sub_command "metadata", Metadata::Root
    sub_command "sign", Sign
    sub_command "verify", Verify
    sub_command "merge", Merge

    property! database : DB::Connection

    def with_db(&)
      db_file = option("input")

      DB.connect "duckdb://#{db_file}" do |database|
        yield database
      end
    end

    def run
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
