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
        {
          "init",
          ->(args: Array(Argument)) {Command::Init.new(args, root, "init").run}
        },
        {
          "dataset:list",
          ->(args: Array(Argument)) {Command::Dataset::List.new(args, root, "dataset list").run}
        },
        {
          "dataset:create",
          ->(args: Array(Argument)) {Command::Dataset::Create.new(args, root, "dataset create").run}
        },
        {
          "dataset:delete",
          ->(args: Array(Argument)) {Command::Dataset::Delete.new(args, root, "dataset delete").run}
        },
        # {
        #   "dataset:update",
        #   ->(args: Array(Argument)) {Command::Dataset::Update.new(args, root, "dataset update").run}
        # },
        {
          "entry:list",
          ->(args: Array(Argument)) {Command::Entry::List.new(args, root, "entry list").run}
        },
        {
          "entry:create",
          ->(args: Array(Argument)) {Command::Entry::Create.new(args, root, "entry create").run}
        },
        {
          "entry:delete",
          ->(args: Array(Argument)) {Command::Entry::Delete.new(args, root, "entry delete").run}
        },
        # {
        #   "entry:update",
        #   ->(args: Array(Argument)) {Command::Entry::Update.new(args, root, "entry update").run}
        # },
        {
          "media:list",
          ->(args: Array(Argument)) {Command::Media::List.new(args, root, "media list").run}
        },
        {
          "media:create",
          ->(args: Array(Argument)) {Command::Media::Create.new(args, root, "media create").run}
        },
        {
          "media:delete",
          ->(args: Array(Argument)) {Command::Media::Delete.new(args, root, "media delete").run}
        },
        # {
        #   "media:update",
        #   ->(args: Array(Argument)) {Command::Media::Update.new(args, root, "media update").run}
        # },
        {
          "annotation:list",
          ->(args: Array(Argument)) {Command::Annotation::List.new(args, root, "annotation list").run}
        },
        {
          "annotation:create",
          ->(args: Array(Argument)) {Command::Annotation::Create.new(args, root, "annotation create").run}
        },
        {
          "annotation:delete",
          ->(args: Array(Argument)) {Command::Annotation::Delete.new(args, root, "annotation delete").run}
        },
        # {
        #   "annotation:update",
        #   ->(args: Array(Argument)) {Command::Annotation::Update.new(args, root, "annotation update").run}
        # },
      ].as(Array(Tuple(String, Proc(Array(Command::Argument), (DB::ExecResult | Nil)))))

      File.open(input, "r") do |file|
        i = 1
        begin
          root.database.exec("BEGIN TRANSACTION")
          file.each_line do |line|
            # Here you would parse the JSON line and append it to the UPD.
            # This is a placeholder for the actual append logic.

            # TODO: Use of JSON Pull Parser for efficiency.

            appendInstruction = AppendInstruction.from_json(line.strip)

            command = append_commands.find(&.[0].==(appendInstruction.command))

            if !command
              raise "command not found: #{appendInstruction.command} (line #{i})"
            else
              command[1]
              .call(
                appendInstruction.args.map do |k, v| # mapping from_json ?
                  Argument.new(k, :optlong, v.to_json.to_s)
                end
              )
            end
            i+=1
          end
          root.database.exec("COMMIT")
        rescue e
          puts e
          root.database.exec("ROLLBACK")
        end
      end
    end
  end
end
