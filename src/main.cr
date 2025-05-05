require "admiral"

require "./commands/**"
require "./data/**"

require "log"

Log.define_formatter LogFormat, "#{severity} | #{message}"

Commands::Root.start