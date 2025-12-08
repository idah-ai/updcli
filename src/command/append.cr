require "./base"
require "./init"
require "json"

module Command
  record AppendInstruction, command : String, args : Hash(String, JSON::Any) do
    include JSON::Serializable

    def to_s
      "AppendInstruction(#{command}, :#{args})"
    end
  end

  class Append < Base
    description "append multiple records into the UPD file. Use jsonl format."
    option "input", "i",
      "Path to the input jsonl file. Default to /dev/stdin", required: false, type: :string
    option "force", "f",
      "Force append and overwrite existing records", required: false, type: :bool

    def run_impl
      input = option("input") || "/dev/stdin"

      File.open(input, "r") do |file|
        i = 1
        begin
          root.database.exec("BEGIN TRANSACTION")
          file.each_line do |line|
            # Here you would parse the JSON line and append it to the UPD.
            # This is a placeholder for the actual append logic.

            # TODO: Use of JSON Pull Parser for efficiency.

            appendInstruction = AppendInstruction.from_json(line.strip)

            args = appendInstruction.args.map do |k, v| # mapping from_json ?
              Argument.new(k, :optlong, v.to_s)
            end # multi level sub commands args ?

            command = root.class.get_command appendInstruction.command.split(":")

            if !command
              raise "command not found: #{appendInstruction.command} (line #{i})"
            else
              command.for(args, root).run
            end
            i+=1
          end
          root.database.exec("COMMIT")
        rescue e
          puts e
          root.database.exec("ROLLBACK")
          raise e
        end
      end
    end
  end
end
