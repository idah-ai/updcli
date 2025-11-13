require "./base"

module Command
  class Append < Base
    description "append multiple records into the UPD file. Use jsonl format."
    option "force", "f",
      "Force append and overwrite existing records", required: false, type: :bool
    option "input", "i",
      "Path to the input jsonl file. Default to /dev/stdin", required: false

    def run_impl
      input = option("input") || "/dev/stdin"

      File.open(input, "r") do |file|
        file.each_line do |line|
          # Here you would parse the JSON line and append it to the UPD.
          # This is a placeholder for the actual append logic.

          # TODO: Use of JSON Pull Parser for efficiency.
          puts "Appending record: #{line.strip}"
        end
      end

      print_help
    end
  end
end
