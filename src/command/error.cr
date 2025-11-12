module Command
  class Error < Exception
    getter command : Base

    def initialize(message, @command)
      super(message)
    end
  end
end