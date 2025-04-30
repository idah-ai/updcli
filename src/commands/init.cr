module Commands
  class Init < Admiral::Command
    define_help description: "List all datasets in the file"

    def root
      parent.as(Commands::Root)
    end

    def run
      Data::Init.new(root.flags.filename).call()
    end
  end
end
