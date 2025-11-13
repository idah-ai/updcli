require "duckdb"
require "log"

require "./command/**"

Log.define_formatter LogFormat, "#{severity} | #{message}"

Command::Parser.parse(ARGV).tap do |args|
  command = Command::Root.new(args)
  command.run
rescue e : Command::Error
  STDERR.puts e.message
  e.command.print_help
  exit 1
end
