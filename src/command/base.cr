module Command
  # Base class for creating command-line interfaces.
  abstract class Base
    class_property self_options = {} of String => {short: String, description: String, default: String?, required: Bool, type: Symbol}
    class_property self_positionals = [] of {name: String, description: String, type: Symbol, required: Bool}
    class_property self_sub_commands = {} of String => Command::Base.class
    class_property self_description : String?

    # Defines a command-line option.
    def self.option(long : String, short : String, description : String = "", default : String? = nil, required : Bool = false, type : Symbol = :bool)
      self_options[long] = {short: short, description: description, default: default, required: required, type: type}
    end

    # Defines a positional argument.
    def self.positional(name : String, description : String = "", type : Symbol = :string, required : Bool = true)
      self_positionals << {name: name, description: description, type: type, required: required}
    end

    # Defines a subcommand.
    def self.sub_command(name : String, command : Command::Base.class)
      self_sub_commands[name] = command
    end

    def self.description(text : String)
      self.self_description = text
    end

    @options = {} of String => String
    @positionals = [] of String
    @sub_command_instance : Command::Base?
    getter sub_command_instance
    @root : Command::Base?
    @name : String

    def initialize(args : Array(Argument), root : Command::Base? = nil, name : String? = nil)
      @root = root
      @name = name || ARGV.fetch(0, "command")
      process(args)
    end

    # Access the parent command.
    def parent(t : T.class = Command::Base) : T? forall T
      @root.as(T | Nil)
    end

    # Access the root command.
    def root(t : T.class = Command::Base) : T forall T
      if (root = @root)
        root.root(t)
      else
        if self.is_a?(T)
          self.as(T)
        else
          raise "Root command is not of type #{T.name}"
        end
      end
    end

    # Gets the value of a parsed option.
    def option(name : String) : String?
      @options[name]? || self.class.self_options[name][:default]?
    end

    # Gets the array of parsed positional arguments.
    def positional : Array(String)
      @positionals
    end

    def error!(message)
      raise Command::Error.new(message, self)
    end

    def print_help
      parts = ["Usage:", @name]
      parts << "[options]" if self.class.self_options.any?
      parts << "[subcommand]" if self.class.self_sub_commands.any?
      self.class.self_positionals.each do |p|
        parts << (p[:required] ? "<#{p[:name]}>" : "[#{p[:name]}]")
      end
      puts parts.join(" ")

      if desc = self.class.self_description
        puts
        puts desc
      end

      if self.class.self_options.any?
        puts
        puts "Options:"
        self.class.self_options.each do |long, opt_def|
          short = if s = opt_def[:short]?
                    "-#{s},"
                  else
                    "   "
                  end
          default_str = if d = opt_def[:default]?
                          " (default: #{d})"
                        else
                          ""
                        end
          puts "  #{short} --#{long.ljust(20)} #{opt_def[:description]}#{default_str}"
        end
      end

      if self.class.self_positionals.any?
        puts
        puts "Arguments:"
        self.class.self_positionals.each do |pos_def|
          puts "  #{pos_def[:name].ljust(24)} #{pos_def[:description]}"
        end
      end

      if self.class.self_sub_commands.any?
        puts
        puts "Subcommands:"
        self.class.self_sub_commands.keys.each do |name|
          puts "  #{name}"
        end
      end
    end

    # Processes the parsed arguments.
    def process(args : Array(Argument))
      # Find the subcommand first.
      sub_command_index = args.index do |arg|
        arg.type == :pos && self.class.self_sub_commands.has_key?(arg.name)
      end

      parent_args : Array(Argument)

      if sub_command_index
        sub_command_arg = args[sub_command_index]
        sub_command_class = self.class.self_sub_commands[sub_command_arg.name]

        parent_args = args.first(sub_command_index)
        child_args = args[(sub_command_index + 1)..]

        @sub_command_instance = sub_command_class.new(child_args, root: self, name: sub_command_arg.name)
      else
        parent_args = args
      end

      # Now, process the parent_args for the current command.
      remaining_args = parent_args.dup

      # 1. Consume options for the current command
      while arg = remaining_args.first?
        break unless arg.type.in?(:optlong, :optshort)
        remaining_args.shift

        option_def = self.class.self_options.find do |long, opt_def|
          long == arg.name || opt_def[:short] == arg.name
        end

        raise Error.new("Illegal option for command '#{@name}': #{arg.name}", self) unless option_def

        long_name, opt_def_values = option_def
        if opt_def_values[:type] == :string
          if arg.value.is_a?(String)
            # Long option with =, e.g., --foo=bar
            @options[long_name] = arg.value.as(String)
          else
            # Value is the next argument
            value_arg = remaining_args.shift?
            if value_arg.nil? || value_arg.type != :pos
              raise Error.new("Option --#{long_name} requires a value.", self)
            end
            @options[long_name] = value_arg.name
          end
        else
          # This is a boolean flag.
          @options[long_name] = arg.value.to_s
        end
      end

      # 2. The rest are positionals for this command
      @positionals = remaining_args.select(&.type.==(:pos)).map(&.name)

      unexpected_opts = remaining_args.reject(&.type.==(:pos))
      if unexpected_opts.any?
        raise Error.new("Unexpected arguments for command '#{@name}': #{unexpected_opts.map(&.name).join(" ")}", self)
      end

      # 3. Validations
      self.class.self_options.each do |long, opt_def|
        if opt_def[:required] && !@options.has_key?(long) && !opt_def[:default]
          raise Error.new("Missing required option for command '#{@name}': --#{long}", self)
        end
      end

      self.class.self_positionals.each_with_index do |pos_def, i|
        if pos_def[:required] && i >= @positionals.size
          raise Error.new("Missing required positional argument for command '#{@name}': #{pos_def[:name]}", self)
        end
      end
    end

    # Executes the command.
    def run
      if sub_cmd = @sub_command_instance
        sub_cmd.run
      else
        run_impl
      end
    end

    # The implementation logic for the command.
    abstract def run_impl
  end
end
