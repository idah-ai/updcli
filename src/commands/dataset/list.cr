
module Commands
  module Dataset
    class List < Admiral::Command
      define_help description: "List all datasets in the file"

      def root
        parent.as(Commands::Dataset::Root).root
      end

      def run
        Data::Dataset.new(root.flags.filename).list
      end
    end
  end
end