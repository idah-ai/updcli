module Commands
  class Init < Admiral::Command
    define_help description: "Initialize a new datset file"

    def root
      parent.as(Commands::Root)
    end

    def run
      Data::Init.new(root.flags.filename).call
      Log.info{ "init #{root.flags.filename}" }
    end
  end
end
