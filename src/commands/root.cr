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
    define_help

    rescue_from(Exception) do |e|
      STDERR.puts e.message
      puts
      puts help
      exit -1
    end

    def run
      puts help
      exit -1
    end

    def self.start
      new.parse_and_run
    end

  end
end
