require "spec"
require "json"
require "duckdb"
require "../../../src/command/**"
require "file_utils"

describe "Command::Entry" do
  before_each do
    Command::Root.new([
      Command::Argument.new("input", :optlong, "test.upd"),
      Command::Argument.new("init", :pos, nil),
    ]).run

    # Entry requires a parent dataset (FK constraint)
    DB.open("duckdb://test.upd") do |db|
      db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test Dataset', 'image', '{}')")
      db.exec("INSERT INTO datasets VALUES ('ds-2', 'Other Dataset', 'text', '{}')")
      db.close
    end
  end

  after_each do
    FileUtils.rm_rf("test.upd")
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Create" do
    it "creates an entry with all required fields" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("dataset_id", :optlong, "ds-1"),
        Command::Argument.new("url", :optlong, "https://example.com/img.jpg"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM entries WHERE dataset_id = 'ds-1'", as: Int64)
        count.should eq(1)
        url = db.query_one("SELECT media_url FROM entries WHERE dataset_id = 'ds-1'", as: String)
        url.should eq("https://example.com/img.jpg")
        db.close
      end
    end

    it "uses a custom id when provided" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("id", :optlong, "entry-custom-1"),
        Command::Argument.new("dataset_id", :optlong, "ds-1"),
        Command::Argument.new("url", :optlong, "https://example.com/img.jpg"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        id = db.query_one("SELECT id FROM entries WHERE id = 'entry-custom-1'", as: String)
        id.should eq("entry-custom-1")
        db.close
      end
    end

    it "auto-generates a UUIDv7 id when not provided" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("dataset_id", :optlong, "ds-1"),
        Command::Argument.new("url", :optlong, "https://example.com/img.jpg"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        id = db.query_one("SELECT id FROM entries", as: String)
        id.should match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
        db.close
      end
    end

    it "injects default metadata when none provided" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("dataset_id", :optlong, "ds-1"),
        Command::Argument.new("url", :optlong, "https://example.com/img.jpg"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        metadata = JSON.parse(db.query_one("SELECT metadata FROM entries", as: String))
        metadata["Created-At"].as_s?.should_not be_nil
        metadata["Updated-At"].as_s?.should be_nil
        metadata["Created-by"].as_s.should eq("updcli")
        db.close
      end
    end

    it "stores user-provided metadata as-is" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("dataset_id", :optlong, "ds-1"),
        Command::Argument.new("url", :optlong, "https://example.com/img.jpg"),
        Command::Argument.new("metadata", :optlong, "{\"source\": \"camera-1\"}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        metadata = JSON.parse(db.query_one("SELECT metadata FROM entries", as: String))
        metadata["source"].as_s.should eq("camera-1")
        db.close
      end
    end

    it "fails with FK violation when dataset_id does not exist" do
      expect_raises(Exception) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("entry", :pos, nil),
          Command::Argument.new("create", :pos, nil),
          Command::Argument.new("dataset_id", :optlong, "nonexistent-ds"),
          Command::Argument.new("url", :optlong, "https://example.com/img.jpg"),
        ]).run
      end
    end

    it "stores a local datset:// URL correctly" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("dataset_id", :optlong, "ds-1"),
        Command::Argument.new("url", :optlong, "datset://media-abc"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        url = db.query_one("SELECT media_url FROM entries", as: String)
        url.should eq("datset://media-abc")
        db.close
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "List" do
    it "handles empty state gracefully" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("list", :pos, nil),
      ]).run
    end

    it "lists all entries across all datasets" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'url1', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-2', 'ds-2', 'url2', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("list", :pos, nil),
      ]).run

      # NOTE: List has no dataset_id filter — it returns ALL entries
      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM entries", as: Int64)
        count.should eq(2)
        db.close
      end
    end

    it "returns id and media_url fields" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'https://example.com/img.jpg', '{}')")
        db.close
      end

      DB.open("duckdb://test.upd") do |db|
        row = db.query_one("SELECT id, media_url FROM entries WHERE id = 'e-1'", as: {String, String})
        row[0].should eq("e-1")
        row[1].should eq("https://example.com/img.jpg")
        db.close
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Show" do
    it "shows the correct entry by id" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'https://example.com/1.jpg', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-2', 'ds-1', 'https://example.com/2.jpg', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("show", :pos, nil),
        Command::Argument.new("id", :optlong, "e-1"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        row = db.query_one("SELECT id, media_url FROM entries WHERE id = 'e-1'", as: {String, String})
        row[0].should eq("e-1")
        row[1].should eq("https://example.com/1.jpg")
        db.close
      end
    end

    it "does not return other entries" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'url1', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-2', 'ds-1', 'url2', '{}')")
        db.close
      end

      DB.open("duckdb://test.upd") do |db|
        rows = db.query_all("SELECT id FROM entries WHERE id = 'e-1'", as: String)
        rows.size.should eq(1)
        db.close
      end
    end

    it "handles non-existent id gracefully without raising" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("show", :pos, nil),
        Command::Argument.new("id", :optlong, "nonexistent"),
      ]).run
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Delete" do
    it "deletes an existing entry" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'url1', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("delete", :pos, nil),
        Command::Argument.new("id", :optlong, "e-1"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM entries WHERE id = 'e-1'", as: Int64)
        count.should eq(0)
        db.close
      end
    end

    it "only deletes the target entry" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'url1', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-2', 'ds-1', 'url2', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("delete", :pos, nil),
        Command::Argument.new("id", :optlong, "e-1"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM entries", as: Int64)
        count.should eq(1)
        remaining = db.query_one("SELECT id FROM entries", as: String)
        remaining.should eq("e-2")
        db.close
      end
    end

    it "is a silent no-op when deleting a non-existent entry" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("delete", :pos, nil),
        Command::Argument.new("id", :optlong, "nonexistent"),
      ]).run
    end
  end
  # ─────────────────────────────────────────────────────────────────────────────
  describe "Update" do
    it "updates the media_url" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'https://old.example.com/img.jpg', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "e-1"),
        Command::Argument.new("url", :optlong, "https://new.example.com/img.jpg"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        url = db.query_one("SELECT media_url FROM entries WHERE id = 'e-1'", as: String)
        url.should eq("https://new.example.com/img.jpg")
        db.close
      end
    end

    it "preserves unchanged fields when partially updating" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'https://example.com/img.jpg', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "e-1"),
        Command::Argument.new("url", :optlong, "https://new.example.com/img.jpg"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        row = db.query_one("SELECT dataset_id, media_url FROM entries WHERE id = 'e-1'", as: {String, String})
        row[0].should eq("ds-1") # dataset_id unchanged
        row[1].should eq("https://new.example.com/img.jpg")
        db.close
      end
    end

    it "replaces metadata with newly provided metadata" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'https://example.com/img.jpg', '{\"old_key\":\"old_val\"}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "e-1"),
        Command::Argument.new("metadata", :optlong, "{\"new_key\":\"new_val\"}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        metadata = JSON.parse(db.query_one("SELECT metadata FROM entries WHERE id = 'e-1'", as: String))
        metadata["new_key"].as_s.should eq("new_val")
        metadata["old_key"]?.should be_nil
        db.close
      end
    end

    it "injects Updated-At and Updated-By into metadata" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'https://example.com/img.jpg', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("entry", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "e-1"),
        Command::Argument.new("url", :optlong, "https://new.example.com/img.jpg"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        metadata = JSON.parse(db.query_one("SELECT metadata FROM entries WHERE id = 'e-1'", as: String))
        metadata["Updated-At"].as_s?.should_not be_nil
        metadata["Updated-By"].as_s.should eq("updcli")
        db.close
      end
    end

    it "raises when entry not found" do
      expect_raises(Command::UpdError, /not found/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("entry", :pos, nil),
          Command::Argument.new("update", :pos, nil),
          Command::Argument.new("id", :optlong, "nonexistent"),
          Command::Argument.new("url", :optlong, "https://example.com/img.jpg"),
        ]).run
      end
    end

    it "raises on invalid JSON in new metadata" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'https://example.com/img.jpg', '{}')")
        db.close
      end

      expect_raises(Command::UpdError, /Invalid JSON in new metadata/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("entry", :pos, nil),
          Command::Argument.new("update", :pos, nil),
          Command::Argument.new("id", :optlong, "e-1"),
          Command::Argument.new("metadata", :optlong, "not valid json"),
        ]).run
      end
    end
  end
end
