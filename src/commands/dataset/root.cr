require "./list"

module Commands
  module Dataset
    class Root < Admiral::Command
      # register_sub_command create: Commands::Dataset::Create
      # register_sub_command delete: Commands::Dataset::Delete
      define_help description: "Operations on datasets"

      register_sub_command list, Commands::Dataset::List

      # register_sub_command show: Commands::Dataset::Show
      def root
        parent.as(Commands::Root)
      end

      def run
        puts "Usage: datset -f <filename> dataset <command> [options]"
        puts "paren asdt: #{root.flags.filename}"
        puts_version
        puts_help
      end
    end
  end
end