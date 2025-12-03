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

      append_commands = [
        [
          "init",
          ->(args: Array(Argument)) {Command::Init.new(args, root).run}
        ],
        [
          "dataset:list",
          ->(args: Array(Argument)) {Command::Dataset::List.new(args, root).run}
        ],
        [
          "dataset:create",
          ->(args: Array(Argument)) {Command::Dataset::Create.new(args, root).run}
        ],
        [
          "dataset:delete",
          ->(args: Array(Argument)) {Command::Dataset::Delete.new(args, root).run}
        ],
        # [
        #   "dataset:update",
        #   ->(args: Array(Argument)) {Command::Dataset::Update.new(args, root).run}
        # ],
        [
          "entry:create",
          ->(args: Array(Argument)) {Command::Entry::Create.new(args, root).run}
        ],
        [
          "entry:delete",
          ->(args: Array(Argument)) {Command::Entry::Delete.new(args, root).run}
        ],
        # [
        #   "entry:update",
        #   ->(args: Array(Argument)) {Command::Entry::Update.new(args, root).run}
        # ],
        [
          "media:create",
          ->(args: Array(Argument)) {Command::Media::Create.new(args, root).run}
        ],
        [
          "media:delete",
          ->(args: Array(Argument)) {Command::Media::Delete.new(args, root).run}
        ],
        # [
        #   "media:update",
        #   ->(args: Array(Argument)) {Command::Media::Update.new(args, root).run}
        # ],
        [
          "annotation:create",
          ->(args: Array(Argument)) {Command::Annotation::Create.new(args, root).run}
        ],
        [
          "annotation:delete",
          ->(args: Array(Argument)) {Command::Annotation::Delete.new(args, root).run}
        ],
        # [
        #   "annotation:update",
        #   ->(args: Array(Argument)) {Command::Annotation::Update.new(args, root).run}
        # ],
      ]

      File.open(input, "r") do |file|
        i = 1
        file.each_line do |line|
          # Here you would parse the JSON line and append it to the UPD.
          # This is a placeholder for the actual append logic.

          # TODO: Use of JSON Pull Parser for efficiency.

          appendInstruction = AppendInstruction.from_json(line.strip)
          puts appendInstruction

          command = append_commands.find(&.[0].==(appendInstruction.command))

          if !command
            raise "command not found: #{appendInstruction.command} (line #{i})"
          else
            command[1]
            .as(Proc(Array(Argument), Nil)) #...
            .call(
              appendInstruction.args.map do |k, v| # mapping from_json ?
                Argument.new(k, :optlong, v.to_s)
              end
            )
          end
          i+=1
        end
      end
    end
  end
end
