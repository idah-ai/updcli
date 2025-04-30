require "option_parser"
require "./**"

module Commands
  class Root < Admiral::Command
    define_help description: "Operate over datset file format"

    define_flag filename : String,
      description: "The datset filename",
      long: :file,
      short: :f,
      required: true


    # register_sub_command planet : Planetary
    register_sub_command ds, Commands::Dataset::Root
    register_sub_command init, Commands::Init

    # register_sub_command metadata : Commands::Metadata::Root
    # register_sub_command entry    : Commands::Entry::Root
    # register_sub_command media    : Commands::Media::Root

    # register_sub_command version  : Commands::Version

    def run
      puts "Usage: datset -f <filename> <command> [options]"
      puts "filename: #{flags.filename}"
      puts_help
    end

    def self.start
      new.parse_and_run
    end

  end
end
