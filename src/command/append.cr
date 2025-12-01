require "./base"
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
    option "force", "f",
      "Force append and overwrite existing records", required: false, type: :bool
    option "input", "i",
      "Path to the input jsonl file. Default to /dev/stdin", required: false

    def run_impl
      input = option("input") || "/dev/stdin"

      append_commands = [
        [
          "dataset:create",
          ->(args: Array(Argument)) {Command::Dataset::Create.new(args, self.root).run_impl}
        ],
        [
          "dataset:delete",
          ->(args: Array(Argument)) {Command::Dataset::Delete.new(args, self.root).run_impl}
        ],
        # [
        #   "dataset:update",
        #   ->(args: Array(Argument)) {Command::Dataset::Update.new(args, self.root).run_impl}
        # ],
        [
          "entry:create",
          ->(args: Array(Argument)) {Command::Entry::Create.new(args, self.root).run_impl}
        ],
        [
          "entry:delete",
          ->(args: Array(Argument)) {Command::Entry::Delete.new(args, self.root).run_impl}
        ],
        # [
        #   "entry:update",
        #   ->(args: Array(Argument)) {Command::Entry::Update.new(args, self.root).run_impl}
        # ],
        [
          "media:create",
          ->(args: Array(Argument)) {Command::Media::Create.new(args, self.root).run_impl}
        ],
        [
          "media:delete",
          ->(args: Array(Argument)) {Command::Media::Delete.new(args, self.root).run_impl}
        ],
        # [
        #   "media:update",
        #   ->(args: Array(Argument)) {Command::Media::Update.new(args, self.root).run_impl}
        # ],
        [
          "annotation:create",
          ->(args: Array(Argument)) {Command::Annotation::Create.new(args, self.root).run_impl}
        ],
        [
          "annotation:delete",
          ->(args: Array(Argument)) {Command::Annotation::Delete.new(args, self.root).run_impl}
        ],
        # [
        #   "annotation:update",
        #   ->(args: Array(Argument)) {Command::Annotation::Update.new(args, self.root).run_impl}
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
