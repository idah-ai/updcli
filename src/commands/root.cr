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

    define_flag quiet : Bool,
      description: "Do not output informations",
      long: :quiet,
      short: :q

    define_flag verbose : Bool,
      description: "Output debugging informations",
      long: :verbose,
      short: :v

    # register_sub_command planet : Planetary
    register_sub_command ds, Commands::Dataset::Root
    register_sub_command init, Commands::Init
    register_sub_command metadata, Commands::Metadata::Root
    # register_sub_command entry    : Commands::Entry::Root
    # register_sub_command media    : Commands::Media::Root
    # register_sub_command version  : Commands::Version

    rescue_from(Exception) do |e|
      Log.fatal{ "#{e.message}\n" }
      Log.fatal{ help }
      exit -1
    end

    def before_run
      if flags.quiet && flags.verbose
        raise "Cannot activate verbose and quiet at the same time."
      end

      if flags.quiet
        Log.setup(:error, Log::IOBackend.new(formatter: LogFormat))
      elsif flags.verbose
        Log.setup(:debug, Log::IOBackend.new(formatter: LogFormat))
      else
        Log.setup(:info, Log::IOBackend.new(formatter: LogFormat))
      end
    end

    def run
      Log.fatal{ help }
      exit -1
    end

    def self.start
      new.call
    end

  end
end
