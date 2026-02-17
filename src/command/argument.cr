module Command
  # Represents a parsed command-line argument.
  record Argument, name : String, type : Symbol, value : Bool | String | Nil do
    def to_s
      "Argument(#{name}, :#{type}, #{value.inspect})"
    end
  end
end
