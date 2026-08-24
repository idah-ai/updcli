require "spec"
require "json"
require "duckdb"
require "file_utils"
require "../../src/command/**"

# Helper: initialise a fresh UPD file at the given path
def init_upd(path : String)
  Command::Root.new([
    Command::Argument.new("input", :optlong, path),
    Command::Argument.new("init", :pos, nil),
  ]).run
end

describe "Command::Merge" do

  before_each do
    init_upd("target.upd")
    init_upd("source.upd")
  end

  after_each do
    FileUtils.rm_rf("target.upd")
    FileUtils.rm_rf("source.upd")
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "datasets" do
    it "merges datasets from source into target" do
      DB.open("duckdb://source.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Source Dataset', 'image', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "target.upd"),
        Command::Argument.new("merge", :pos, nil),
        Command::Argument.new("source", :optlong, "source.upd"),
      ]).run

      DB.open("duckdb://target.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM datasets WHERE id = 'ds-1'", as: Int64)
        count.should eq(1)
        name = db.query_one("SELECT name FROM datasets WHERE id = 'ds-1'", as: String)
        name.should eq("Source Dataset")
        db.close
      end
    end

    it "merges multiple datasets at once" do
      DB.open("duckdb://source.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'First', 'image', '{}')")
        db.exec("INSERT INTO datasets VALUES ('ds-2', 'Second', 'text', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "target.upd"),
        Command::Argument.new("merge", :pos, nil),
        Command::Argument.new("source", :optlong, "source.upd"),
      ]).run

      DB.open("duckdb://target.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM datasets", as: Int64)
        count.should eq(2)
        db.close
      end
    end

    it "preserves datasets already in the target" do
      DB.open("duckdb://target.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-existing', 'Existing', 'image', '{}')")
        db.close
      end

      DB.open("duckdb://source.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-new', 'New', 'text', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "target.upd"),
        Command::Argument.new("merge", :pos, nil),
        Command::Argument.new("source", :optlong, "source.upd"),
      ]).run

      DB.open("duckdb://target.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM datasets", as: Int64)
        count.should eq(2)
        db.close
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "entries" do
    it "merges entries along with their parent datasets" do
      DB.open("duckdb://source.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Dataset', 'image', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'https://example.com/img.jpg', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "target.upd"),
        Command::Argument.new("merge", :pos, nil),
        Command::Argument.new("source", :optlong, "source.upd"),
      ]).run

      DB.open("duckdb://target.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM entries WHERE id = 'e-1'", as: Int64)
        count.should eq(1)
        url = db.query_one("SELECT media_url FROM entries WHERE id = 'e-1'", as: String)
        url.should eq("https://example.com/img.jpg")
        db.close
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "annotations" do
    it "merges annotations along with their parent entries and datasets" do
      DB.open("duckdb://source.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Dataset', 'image', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'https://example.com/img.jpg', '{}')")
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', 'cat', '{}', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "target.upd"),
        Command::Argument.new("merge", :pos, nil),
        Command::Argument.new("source", :optlong, "source.upd"),
      ]).run

      DB.open("duckdb://target.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM annotations WHERE id = 'a-1'", as: Int64)
        count.should eq(1)
        row = db.query_one("SELECT shape_type, category, properties FROM annotations WHERE id = 'a-1'", as: {String, String, String})
        row[0].should eq("bbox")
        row[1].should eq("cat")
        JSON.parse(row[2]).should eq(JSON.parse("{}"))
        db.close
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "medias" do
    it "merges media blobs from source into target" do
      DB.open("duckdb://source.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', '', ?, 'image/jpeg', '{}')", "blob content".to_slice)
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "target.upd"),
        Command::Argument.new("merge", :pos, nil),
        Command::Argument.new("source", :optlong, "source.upd"),
      ]).run

      DB.open("duckdb://target.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM medias WHERE id = 'm-1'", as: Int64)
        count.should eq(1)
        blob = db.query_one("SELECT blob_data FROM medias WHERE id = 'm-1' AND key = ''", as: Bytes)
        String.new(blob).should eq("blob content")
        db.close
      end
    end

    it "merges all variants for the same media id (composite PK)" do
      DB.open("duckdb://source.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', 'full', ?, 'image/jpeg', '{}')", "full".to_slice)
        db.exec("INSERT INTO medias VALUES ('m-1', 'thumbnail', ?, 'image/jpeg', '{}')", "thumb".to_slice)
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "target.upd"),
        Command::Argument.new("merge", :pos, nil),
        Command::Argument.new("source", :optlong, "source.upd"),
      ]).run

      DB.open("duckdb://target.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM medias WHERE id = 'm-1'", as: Int64)
        count.should eq(2)
        db.close
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "conflict resolution: skip (default)" do
    it "skips duplicate datasets by default" do
      DB.open("duckdb://target.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Target Version', 'image', '{}')")
        db.close
      end

      DB.open("duckdb://source.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Source Version', 'text', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "target.upd"),
        Command::Argument.new("merge", :pos, nil),
        Command::Argument.new("source", :optlong, "source.upd"),
      ]).run

      DB.open("duckdb://target.upd") do |db|
        # Only one row — source did not overwrite
        count = db.query_one("SELECT COUNT(*) FROM datasets WHERE id = 'ds-1'", as: Int64)
        count.should eq(1)
        # Target version preserved
        name = db.query_one("SELECT name FROM datasets WHERE id = 'ds-1'", as: String)
        name.should eq("Target Version")
        db.close
      end
    end

    it "skips duplicate entries by default" do
      DB.open("duckdb://target.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Dataset', 'image', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'https://target.com/img.jpg', '{}')")
        db.close
      end

      DB.open("duckdb://source.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Dataset', 'image', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'https://source.com/img.jpg', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "target.upd"),
        Command::Argument.new("merge", :pos, nil),
        Command::Argument.new("source", :optlong, "source.upd"),
      ]).run

      DB.open("duckdb://target.upd") do |db|
        url = db.query_one("SELECT media_url FROM entries WHERE id = 'e-1'", as: String)
        url.should eq("https://target.com/img.jpg") # Target preserved
        db.close
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "conflict resolution: overwrite" do
    it "overwrites duplicate datasets with source version" do
      DB.open("duckdb://target.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Target Version', 'image', '{}')")
        db.close
      end

      DB.open("duckdb://source.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Source Version', 'text', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "target.upd"),
        Command::Argument.new("merge", :pos, nil),
        Command::Argument.new("source", :optlong, "source.upd"),
        Command::Argument.new("strategy", :optlong, "overwrite"),
      ]).run

      DB.open("duckdb://target.upd") do |db|
        row = db.query_one("SELECT name, modality FROM datasets WHERE id = 'ds-1'", as: {String, String})
        row[0].should eq("Source Version")
        row[1].should eq("text")
        db.close
      end
    end

    it "overwrites duplicate media blobs with source version" do
      DB.open("duckdb://target.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', '', ?, 'image/jpeg', '{}')", "old blob".to_slice)
        db.close
      end

      DB.open("duckdb://source.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', '', ?, 'image/jpeg', '{}')", "new blob".to_slice)
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "target.upd"),
        Command::Argument.new("merge", :pos, nil),
        Command::Argument.new("source", :optlong, "source.upd"),
        Command::Argument.new("strategy", :optlong, "overwrite"),
      ]).run

      DB.open("duckdb://target.upd") do |db|
        blob = db.query_one("SELECT blob_data FROM medias WHERE id = 'm-1' AND key = ''", as: Bytes)
        String.new(blob).should eq("new blob")
        db.close
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "full merge (all tables together)" do
    it "merges a fully populated source into an empty target" do
      DB.open("duckdb://source.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Dataset', 'image', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'https://example.com/img.jpg', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-2', 'ds-1', 'https://example.com/img2.jpg', '{}')")
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', 'cat', '{}', '{}')")
        db.exec("INSERT INTO annotations VALUES ('a-2', 'e-2', 'bbox', '{\"x\":10}', 'dog', '{}', '{}')")
        db.exec("INSERT INTO medias VALUES ('m-1', '', ?, 'image/jpeg', '{}')", "blob".to_slice)
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "target.upd"),
        Command::Argument.new("merge", :pos, nil),
        Command::Argument.new("source", :optlong, "source.upd"),
      ]).run

      DB.open("duckdb://target.upd") do |db|
        db.query_one("SELECT COUNT(*) FROM datasets", as: Int64).should eq(1)
        db.query_one("SELECT COUNT(*) FROM entries", as: Int64).should eq(2)
        db.query_one("SELECT COUNT(*) FROM annotations", as: Int64).should eq(2)
        db.query_one("SELECT COUNT(*) FROM medias", as: Int64).should eq(1)
        db.close
      end
    end

    it "does not modify global metadata from the target file" do
      DB.open("duckdb://source.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Dataset', 'image', '{}')")
        # Simulate source having a different Schema-Built-By
        db.exec("UPDATE metadata SET value = '\"source-tool v9.9\"' WHERE key = 'Schema-Built-By'")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "target.upd"),
        Command::Argument.new("merge", :pos, nil),
        Command::Argument.new("source", :optlong, "source.upd"),
      ]).run

      DB.open("duckdb://target.upd") do |db|
        # metadata table is NOT merged — target's Schema-Built-By is preserved
        built_by = db.query_one("SELECT value FROM metadata WHERE key = 'Schema-Built-By'", as: String)
        built_by.should eq("\"updcli v1.0\"")
        db.close
      end
    end

    it "is an atomic transaction — rolls back all tables on failure" do
      # Recreate source.upd from scratch WITHOUT FK constraints so we can
      # insert a deliberately broken entry. The merge into the FK-enforced
      # target will then fail, proving the rollback works.
      FileUtils.rm_rf("source.upd")
      DB.open("duckdb://source.upd") do |db|
        db.exec("CREATE TABLE datasets (id VARCHAR PRIMARY KEY, name VARCHAR, modality VARCHAR, metadata VARCHAR DEFAULT '{}')")
        db.exec("CREATE TABLE entries  (id VARCHAR PRIMARY KEY, dataset_id VARCHAR, media_url VARCHAR, metadata VARCHAR DEFAULT '{}')")
        db.exec("CREATE TABLE annotations (id VARCHAR PRIMARY KEY, entry_id VARCHAR, shape_type VARCHAR, shape_args VARCHAR, category VARCHAR, properties VARCHAR DEFAULT '{}', metadata VARCHAR DEFAULT '{}')")
        db.exec("CREATE TABLE medias (id VARCHAR NOT NULL, key VARCHAR NOT NULL, blob_data BLOB, media_type VARCHAR, metadata VARCHAR DEFAULT '{}', PRIMARY KEY (id, key))")
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Dataset', 'image', '{}')")
        # This entry points to a dataset that does NOT exist in the target
        db.exec("INSERT INTO entries VALUES ('e-bad', 'ds-nonexistent', 'url', '{}')")
        db.close
      end

      DB.open("duckdb://target.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Existing', 'image', '{}')")
        db.close
      end

      expect_raises(Command::UpdError, /rolled back/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "target.upd"),
          Command::Argument.new("merge", :pos, nil),
          Command::Argument.new("source", :optlong, "source.upd"),
        ]).run
      end

      # Target should be unchanged — no partial merge
      DB.open("duckdb://target.upd") do |db|
        db.query_one("SELECT COUNT(*) FROM entries", as: Int64).should eq(0)
        db.close
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "error handling" do
    it "raises when source file does not exist" do
      expect_raises(Command::UpdError, /Source file not found/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "target.upd"),
          Command::Argument.new("merge", :pos, nil),
          Command::Argument.new("source", :optlong, "nonexistent.upd"),
        ]).run
      end
    end

    it "raises on an invalid strategy value" do
      expect_raises(Command::UpdError, /Invalid strategy/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "target.upd"),
          Command::Argument.new("merge", :pos, nil),
          Command::Argument.new("source", :optlong, "source.upd"),
          Command::Argument.new("strategy", :optlong, "upsert"),
        ]).run
      end
    end
  end
end
