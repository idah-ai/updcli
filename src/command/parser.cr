module Command
  # Parses an array of strings into an array of Arguments.
  module Parser
    def self.parse(options : Array(String))
      args = [] of Argument
      remaining_opts = options.dup
      end_of_opts = false

      while opt = remaining_opts.shift?
        if end_of_opts
          args << Argument.new(name: opt, type: :pos, value: nil)
          next
        end

        case opt
        when "--"
          end_of_opts = true
        when /^--([a-zA-Z-_]+)(=(.*))?$/
          match = $~
          key = match[1]
          val = match[3]? || true
          args << Argument.new(name: key, type: :optlong, value: val)
        when /^-(\w+)$/
          key = $1
          key.chars.map do |k|
            args << Argument.new(name: k.to_s, type: :optshort, value: true)
          end
        else
          args << Argument.new(name: opt, type: :pos, value: nil)
        end
      end

      args
    end
  end
end
