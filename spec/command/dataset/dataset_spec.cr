require "spec"
require "json"
require "duckdb"
require "../../../src/command/**"
require "file_utils"

describe "Command::Dataset" do
  before_each do
    Command::Root.new([
      Command::Argument.new("input", :optlong, "test.upd"),
      Command::Argument.new("init", :pos, nil),
    ]).run
  end

  after_each do
    FileUtils.rm_rf("test.upd")
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Create" do
    it "creates a dataset with required fields" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("name", :optlong, "My Dataset"),
        Command::Argument.new("modality", :optlong, "image"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM datasets", as: Int64)
        count.should eq(1)
        row = db.query_one("SELECT name, modality FROM datasets", as: {String, String})
        row[0].should eq("My Dataset")
        row[1].should eq("image")
        db.close
      end
    end

    it "uses a custom id when provided" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("id", :optlong, "custom-id-123"),
        Command::Argument.new("name", :optlong, "Test"),
        Command::Argument.new("modality", :optlong, "text"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        id = db.query_one("SELECT id FROM datasets WHERE id = 'custom-id-123'", as: String)
        id.should eq("custom-id-123")
        db.close
      end
    end

    it "auto-generates a UUIDv7 id when not provided" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("name", :optlong, "Test"),
        Command::Argument.new("modality", :optlong, "image"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        id = db.query_one("SELECT id FROM datasets", as: String)
        id.should match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
        db.close
      end
    end

    it "injects Created-At, Updated-At (null), and Created-by into metadata" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("name", :optlong, "Test"),
        Command::Argument.new("modality", :optlong, "image"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        metadata = JSON.parse(db.query_one("SELECT metadata FROM datasets", as: String))
        metadata["Created-At"].as_s?.should_not be_nil
        metadata["Updated-At"].as_s?.should be_nil
        metadata["Created-by"].as_s.should eq("updcli")
        db.close
      end
    end

    it "merges user-provided metadata with default fields" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("name", :optlong, "Test"),
        Command::Argument.new("modality", :optlong, "image"),
        Command::Argument.new("metadata", :optlong, "{\"source\": \"lab\"}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        metadata = JSON.parse(db.query_one("SELECT metadata FROM datasets", as: String))
        metadata["source"].as_s.should eq("lab")
        metadata["Created-At"].as_s?.should_not be_nil
        metadata["Created-by"].as_s.should eq("updcli")
        db.close
      end
    end

    it "raises on invalid JSON metadata" do
      expect_raises(Command::UpdError, /Invalid JSON metadata/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("dataset", :pos, nil),
          Command::Argument.new("create", :pos, nil),
          Command::Argument.new("name", :optlong, "Test"),
          Command::Argument.new("modality", :optlong, "image"),
          Command::Argument.new("metadata", :optlong, "not valid json"),
        ]).run
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "List" do
    it "handles empty state gracefully" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("list", :pos, nil),
      ]).run
    end

    it "lists all datasets" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Dataset 1', 'image', '{}')")
        db.exec("INSERT INTO datasets VALUES ('ds-2', 'Dataset 2', 'text', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("list", :pos, nil),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM datasets", as: Int64)
        count.should eq(2)
        db.close
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Show" do
    it "shows the correct dataset by id" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'First', 'image', '{}')")
        db.exec("INSERT INTO datasets VALUES ('ds-2', 'Second', 'text', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("show", :pos, nil),
        Command::Argument.new("id", :optlong, "ds-1"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        row = db.query_one("SELECT id, name FROM datasets WHERE id = 'ds-1'", as: {String, String})
        row[0].should eq("ds-1")
        row[1].should eq("First")
        db.close
      end
    end

    it "does not return other datasets" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'First', 'image', '{}')")
        db.exec("INSERT INTO datasets VALUES ('ds-2', 'Second', 'text', '{}')")
        db.close
      end

      DB.open("duckdb://test.upd") do |db|
        rows = db.query_all("SELECT id FROM datasets WHERE id = 'ds-1'", as: String)
        rows.size.should eq(1)
        db.close
      end
    end

    it "handles non-existent id gracefully without raising" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("show", :pos, nil),
        Command::Argument.new("id", :optlong, "nonexistent"),
      ]).run
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Update" do
    it "updates the name" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Old Name', 'image', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "ds-1"),
        Command::Argument.new("name", :optlong, "New Name"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        name = db.query_one("SELECT name FROM datasets WHERE id = 'ds-1'", as: String)
        name.should eq("New Name")
        db.close
      end
    end

    it "updates the modality" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test', 'image', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "ds-1"),
        Command::Argument.new("modality", :optlong, "video"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        modality = db.query_one("SELECT modality FROM datasets WHERE id = 'ds-1'", as: String)
        modality.should eq("video")
        db.close
      end
    end

    it "replaces metadata with newly provided metadata" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test', 'image', '{\"old_key\":\"old_val\"}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "ds-1"),
        Command::Argument.new("metadata", :optlong, "{\"new_key\":\"new_val\"}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        metadata = JSON.parse(db.query_one("SELECT metadata FROM datasets WHERE id = 'ds-1'", as: String))
        metadata["new_key"].as_s.should eq("new_val")
        metadata["old_key"]?.should be_nil
        db.close
      end
    end

    it "preserves unchanged fields when partially updating" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Original', 'image', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "ds-1"),
        Command::Argument.new("name", :optlong, "Updated Name"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        row = db.query_one("SELECT name, modality FROM datasets WHERE id = 'ds-1'", as: {String, String})
        row[0].should eq("Updated Name")
        row[1].should eq("image") # Unchanged
        db.close
      end
    end

    it "injects Updated-At and Updated-By into metadata" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test', 'image', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "ds-1"),
        Command::Argument.new("name", :optlong, "Updated"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        metadata = JSON.parse(db.query_one("SELECT metadata FROM datasets WHERE id = 'ds-1'", as: String))
        metadata["Updated-At"].as_s?.should_not be_nil
        metadata["Updated-By"].as_s.should eq("updcli")
        db.close
      end
    end

    it "raises when dataset not found" do
      expect_raises(Command::UpdError, /not found/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("dataset", :pos, nil),
          Command::Argument.new("update", :pos, nil),
          Command::Argument.new("id", :optlong, "nonexistent"),
          Command::Argument.new("name", :optlong, "New Name"),
        ]).run
      end
    end

    it "raises on invalid JSON in new metadata" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test', 'image', '{}')")
        db.close
      end

      expect_raises(Command::UpdError, /Invalid JSON in new metadata/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("dataset", :pos, nil),
          Command::Argument.new("update", :pos, nil),
          Command::Argument.new("id", :optlong, "ds-1"),
          Command::Argument.new("metadata", :optlong, "not valid json"),
        ]).run
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Delete" do
    it "deletes an existing dataset" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'To Delete', 'image', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("delete", :pos, nil),
        Command::Argument.new("id", :optlong, "ds-1"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM datasets WHERE id = 'ds-1'", as: Int64)
        count.should eq(0)
        db.close
      end
    end

    it "only deletes the target dataset" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Delete Me', 'image', '{}')")
        db.exec("INSERT INTO datasets VALUES ('ds-2', 'Keep Me', 'text', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("delete", :pos, nil),
        Command::Argument.new("id", :optlong, "ds-1"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM datasets", as: Int64)
        count.should eq(1)
        remaining = db.query_one("SELECT id FROM datasets", as: String)
        remaining.should eq("ds-2")
        db.close
      end
    end

    it "is a silent no-op when deleting a non-existent dataset" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("dataset", :pos, nil),
        Command::Argument.new("delete", :pos, nil),
        Command::Argument.new("id", :optlong, "nonexistent"),
      ]).run
    end
  end
end
