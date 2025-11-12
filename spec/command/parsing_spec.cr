require "../spec_helper"

class TestCommand < Command::Base
  description "A test command"

  option "database", "d", "Database name", type: :string
  option "verbose", "v", "Enable verbose mode"

  def run_impl
    # No-op
  end
end

class SubCmd < Command::Base
  description "A subcommand"
  option "sub-opt", "s", "A subcommand option"
  def run_impl; end
end

class RootCmd < Command::Base
  description "A root command"
  option "root-opt", "r", "A root command option"
  sub_command "sub", SubCmd
  def run_impl; end
end

describe Command::Base do
  it "parses short option with value" do
    args = Command::Parser.parse(["-d", "my_db"])
    cmd = TestCommand.new(args)
    cmd.option("database").should eq("my_db")
  end

  it "parses long option with value (space)" do
    args = Command::Parser.parse(["--database", "my_db"])
    cmd = TestCommand.new(args)
    cmd.option("database").should eq("my_db")
  end

  it "parses long option with value (equals)" do
    args = Command::Parser.parse(["--database=my_db"])
    cmd = TestCommand.new(args)
    cmd.option("database").should eq("my_db")
  end

  it "parses boolean short option" do
    args = Command::Parser.parse(["-v"])
    cmd = TestCommand.new(args)
    cmd.option("verbose").should eq("true")
  end

  it "parses boolean long option" do
    args = Command::Parser.parse(["--verbose"])
    cmd = TestCommand.new(args)
    cmd.option("verbose").should eq("true")
  end

  it "raises if value is missing for string option" do
    expect_raises(Command::Error, "Option --database requires a value.") do
      args = Command::Parser.parse(["-d"])
      TestCommand.new(args)
    end
  end

  context "with positional arguments" do
    it "parses a single positional argument" do
      args = Command::Parser.parse(["-d", "db", "pos1"])
      cmd = TestCommand.new(args)
      cmd.option("database").should eq("db")
      cmd.positional.should eq(["pos1"])
    end

    it "parses multiple positional arguments" do
      args = Command::Parser.parse(["-d", "db", "pos1", "pos2"])
      cmd = TestCommand.new(args)
      cmd.option("database").should eq("db")
      cmd.positional.should eq(["pos1", "pos2"])
    end
  end

  context "with subcommands" do
    it "parses subcommand and its options" do
      args = Command::Parser.parse(["-r", "sub", "-s"])
      cmd = RootCmd.new(args)
      cmd.option("root-opt").should eq("true")
      sub_cmd = cmd.sub_command_instance.as(SubCmd)
      sub_cmd.option("sub-opt").should eq("true")
    end

    it "handles -- to separate positional arguments" do
      args = Command::Parser.parse(["-r", "--", "-s"])
      cmd = RootCmd.new(args)
      cmd.option("root-opt").should eq("true")
      cmd.positional.should eq(["-s"])
    end
  end
end
