require "option_parser"
require "sqlite3"

require "./commands/init"

# TODO: Implement the actual logic for each command
filenames = [] of String

command : Commands::Base? = nil

command_block = ->(cmd : Commands::Base) {
  command = cmd
}


parser = OptionParser.new do |parser|
  parser.banner = "Usage: datset [command] [options]"

  Commands::Init.new.parse(parser, command_block)

  parser.on("-v", "--version", "Show version") do
    puts "datset 0.1.0"
    exit
  end

  parser.on("-h", "--help", "Show this help") do
    puts parser
    exit
  end

  parser.invalid_option do |flag|
    STDERR.puts "ERROR: #{flag} is not a valid option."
    STDERR.puts parser
    exit(1)
  end

  parser.unknown_args do |args|
    if args.any?
      STDERR.puts "ERROR: Unknown command: #{args.first}"
    end
    STDERR.puts parser
    exit(1)
  end
end
parser.parse(ARGV)
pp filenames
pp command

if c = command
  c.run
else
  STDERR.puts "ERROR: No command specified."
  STDERR.puts parser
  exit(1)
end

# OptionParser.parse do |parser|
#   parser.banner = "Usage: datset [command] [options]"
#   parser.on("help", "Show this help") { puts parser; exit }
#   parser.on("version", "Show version") { puts "datset 0.1.0"; exit } # TODO: Get version from shard.yml

#   parser.command("init") do |init_parser|
#     init_parser.banner = "Usage: datset init <filename>"
#     init_parser.on("<filename>", "Path to the datset file to create") { |f| filename = f }
#     init_parser.on_invalid_option { |flag| STDERR.puts "init: #{flag} is not a valid option."; exit 1 }
#   end

#   parser.command("info") do |info_parser|
#     info_parser.banner = "Usage: datset info <filename>"
#     info_parser.on("<filename>", "Path to the datset file") { |f| filename = f }
#     info_parser.on_invalid_option { |flag| STDERR.puts "info: #{flag} is not a valid option."; exit 1 }
#   end

#   parser.command("batch") do |batch_parser|
#     batch_parser.banner = "Usage: datset batch <batch_id> [subcommand] [options]"
#     batch_parser.on("<batch_id>", "ID of the batch") { |id| batch_id = id }

#     batch_parser.command("info") do |batch_info_parser|
#       batch_info_parser.banner = "Usage: datset batch <batch_id> info"
#       batch_info_parser.on_invalid_option { |flag| STDERR.puts "batch info: #{flag} is not a valid option."; exit 1 }
#     end

#     batch_parser.command("list") do |batch_list_parser|
#       batch_list_parser.banner = "Usage: datset batch <batch_id> list"
#       batch_list_parser.on_invalid_option { |flag| STDERR.puts "batch list: #{flag} is not a valid option."; exit 1 }
#     end

#     batch_parser.command("entry") do |batch_entry_parser|
#       batch_entry_parser.banner = "Usage: datset batch <batch_id> entry <entry_id>"
#       batch_entry_parser.on("<entry_id>", "ID of the entry") { |id| entry_id = id }
#       batch_entry_parser.on_invalid_option { |flag| STDERR.puts "batch entry: #{flag} is not a valid option."; exit 1 }
#     end

#     batch_parser.command("add") do |batch_add_parser|
#       batch_add_parser.banner = "Usage: datset batch <batch_id> add <entry_data>"
#       # TODO: Define how entry_data is passed (e.g., JSON string, key-value pairs)
#       batch_add_parser.on("<entry_data>", "Data for the new entry") { |data| puts "TODO: Handle entry data: #{data}" }
#       batch_add_parser.on_invalid_option { |flag| STDERR.puts "batch add: #{flag} is not a valid option."; exit 1 }
#     end
#     batch_parser.on_invalid_option { |flag| STDERR.puts "batch: #{flag} is not a valid option."; exit 1 }
#   end

#   parser.command("metadata") do |metadata_parser|
#     metadata_parser.banner = "Usage: datset metadata [subcommand] [options]"

#     metadata_parser.command("show") do |meta_show_parser|
#       meta_show_parser.banner = "Usage: datset metadata show <key-name>"
#       meta_show_parser.on("<key-name>", "Name of the metadata key") { |k| key_name = k }
#       meta_show_parser.on_invalid_option { |flag| STDERR.puts "metadata show: #{flag} is not a valid option."; exit 1 }
#     end

#     metadata_parser.command("del") do |meta_del_parser|
#       meta_del_parser.banner = "Usage: datset metadata del <key-name>"
#       meta_del_parser.on("<key-name>", "Name of the metadata key to delete") { |k| key_name = k }
#       meta_del_parser.on_invalid_option { |flag| STDERR.puts "metadata del: #{flag} is not a valid option."; exit 1 }
#     end

#     metadata_parser.command("list") do |meta_list_parser|
#       meta_list_parser.banner = "Usage: datset metadata list"
#       meta_list_parser.on_invalid_option { |flag| STDERR.puts "metadata list: #{flag} is not a valid option."; exit 1 }
#     end

#     metadata_parser.command("add") do |meta_add_parser|
#       meta_add_parser.banner = "Usage: datset metadata add <key-name> <value>"
#       meta_add_parser.on("<key-name>", "Name of the metadata key") { |k| key_name = k }
#       meta_add_parser.on("<value>", "Value for the metadata key") { |v| value = v }
#       meta_add_parser.on("--stdin", "Read value from standard input") { use_stdin = true }
#       meta_add_parser.on_invalid_option { |flag| STDERR.puts "metadata add: #{flag} is not a valid option."; exit 1 }
#     end
#     metadata_parser.on_invalid_option { |flag| STDERR.puts "metadata: #{flag} is not a valid option."; exit 1 }
#   end

#   parser.on_invalid_option do |flag|
#     STDERR.puts "#{flag} is not a valid option."
#     STDERR.puts parser
#     exit 1
#   end

#   # Extract command and arguments after parsing
#   command = ARGV[0]?
#   subcommand = ARGV[1]?
#   sub_subcommand = ARGV[2]? # For batch entry/add and metadata subcommands

#   # TODO: Add logic to call appropriate functions based on parsed command/subcommands
#   puts "Command: #{command}"
#   puts "Subcommand: #{subcommand}"
#   puts "Sub-Subcommand: #{sub_subcommand}"
#   puts "Filename: #{filename}" if filename != ""
#   puts "Batch ID: #{batch_id}" if batch_id != ""
#   puts "Entry ID: #{entry_id}" if entry_id != ""
#   puts "Key Name: #{key_name}" if key_name != ""
#   puts "Value: #{value}" if value != ""
#   puts "Use STDIN: #{use_stdin}" if use_stdin
# end

# # Placeholder for actual command execution logic
# puts "Datset CLI tool - Placeholder"
