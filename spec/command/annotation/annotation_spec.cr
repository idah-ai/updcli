require "spec"
require "json"
require "duckdb"
require "../../../src/command/**"
require "file_utils"

describe "Command::Annotation" do
  before_each do
    Command::Root.new([
      Command::Argument.new("input", :optlong, "test.upd"),
      Command::Argument.new("init", :pos, nil),
    ]).run

    # Annotations require a parent dataset + entry (FK constraint)
    DB.open("duckdb://test.upd") do |db|
      db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test Dataset', 'image', '{}')")
      db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'https://example.com/img.jpg', '{}')")
      db.exec("INSERT INTO entries VALUES ('e-2', 'ds-1', 'https://example.com/img2.jpg', '{}')")
      db.close
    end
  end

  after_each do
    FileUtils.rm_rf("test.upd")
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Create" do
    it "creates an annotation with all required fields" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("entry_id", :optlong, "e-1"),
        Command::Argument.new("type", :optlong, "bbox"),
        Command::Argument.new("shape", :optlong, "{\"x\":0,\"y\":0,\"w\":100,\"h\":100}"),
        Command::Argument.new("annotation", :optlong, "{\"label\":\"cat\"}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM annotations WHERE entry_id = 'e-1'", as: Int64)
        count.should eq(1)
        row = db.query_one(
          "SELECT shape_type, shape_args, annotation FROM annotations WHERE entry_id = 'e-1'",
          as: {String, String, String}
        )
        row[0].should eq("bbox")
        JSON.parse(row[1])["x"].as_i.should eq(0)
        JSON.parse(row[2])["label"].as_s.should eq("cat")
        db.close
      end
    end

    it "uses a custom id when provided" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("id", :optlong, "ann-custom-1"),
        Command::Argument.new("entry_id", :optlong, "e-1"),
        Command::Argument.new("type", :optlong, "bbox"),
        Command::Argument.new("shape", :optlong, "{\"x\":0}"),
        Command::Argument.new("annotation", :optlong, "{\"label\":\"cat\"}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        id = db.query_one("SELECT id FROM annotations WHERE id = 'ann-custom-1'", as: String)
        id.should eq("ann-custom-1")
        db.close
      end
    end

    it "auto-generates a UUIDv7 id when not provided" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("entry_id", :optlong, "e-1"),
        Command::Argument.new("type", :optlong, "bbox"),
        Command::Argument.new("shape", :optlong, "{\"x\":0}"),
        Command::Argument.new("annotation", :optlong, "{\"label\":\"cat\"}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        id = db.query_one("SELECT id FROM annotations", as: String)
        id.should match(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/)
        db.close
      end
    end

    it "parses and stores shape_args as JSON" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("entry_id", :optlong, "e-1"),
        Command::Argument.new("type", :optlong, "polygon"),
        Command::Argument.new("shape", :optlong, "{\"points\":[[0,0],[100,0],[100,100]]}"),
        Command::Argument.new("annotation", :optlong, "{\"label\":\"road\"}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        shape_args = db.query_one("SELECT shape_args FROM annotations", as: String)
        parsed = JSON.parse(shape_args)
        parsed["points"].as_a.size.should eq(3)
        db.close
      end
    end

    it "parses and stores annotation value as JSON" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("entry_id", :optlong, "e-1"),
        Command::Argument.new("type", :optlong, "bbox"),
        Command::Argument.new("shape", :optlong, "{\"x\":0}"),
        Command::Argument.new("annotation", :optlong, "{\"label\":\"cat\",\"score\":0.95}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        annotation_val = db.query_one("SELECT annotation FROM annotations", as: String)
        parsed = JSON.parse(annotation_val)
        parsed["label"].as_s.should eq("cat")
        parsed["score"].as_f.should eq(0.95)
        db.close
      end
    end

    it "injects default metadata when none provided" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("entry_id", :optlong, "e-1"),
        Command::Argument.new("type", :optlong, "bbox"),
        Command::Argument.new("shape", :optlong, "{\"x\":0}"),
        Command::Argument.new("annotation", :optlong, "{\"label\":\"cat\"}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        metadata = JSON.parse(db.query_one("SELECT metadata FROM annotations", as: String))
        metadata["Created-At"].as_s?.should_not be_nil
        metadata["Updated-At"].as_s?.should be_nil
        metadata["Created-by"].as_s.should eq("updcli")
        db.close
      end
    end

    it "stores user-provided metadata as-is" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("create", :pos, nil),
        Command::Argument.new("entry_id", :optlong, "e-1"),
        Command::Argument.new("type", :optlong, "bbox"),
        Command::Argument.new("shape", :optlong, "{\"x\":0}"),
        Command::Argument.new("annotation", :optlong, "{\"label\":\"cat\"}"),
        Command::Argument.new("metadata", :optlong, "{\"annotator\":\"alice\"}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        metadata = JSON.parse(db.query_one("SELECT metadata FROM annotations", as: String))
        metadata["annotator"].as_s.should eq("alice")
        db.close
      end
    end

    it "fails with FK violation when entry_id does not exist" do
      expect_raises(Exception) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("annotation", :pos, nil),
          Command::Argument.new("create", :pos, nil),
          Command::Argument.new("entry_id", :optlong, "nonexistent-entry"),
          Command::Argument.new("type", :optlong, "bbox"),
          Command::Argument.new("shape", :optlong, "{\"x\":0}"),
          Command::Argument.new("annotation", :optlong, "{\"label\":\"cat\"}"),
        ]).run
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "List" do
    it "handles empty state gracefully" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("list", :pos, nil),
      ]).run
    end

    it "lists all annotations" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', '{\"label\":\"cat\"}', '{}')")
        db.exec("INSERT INTO annotations VALUES ('a-2', 'e-2', 'bbox', '{\"x\":10}', '{\"label\":\"dog\"}', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("list", :pos, nil),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM annotations", as: Int64)
        count.should eq(2)
        db.close
      end
    end

    it "returns id, shape_type, annotation and shape_args fields" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', '{\"label\":\"cat\"}', '{}')")
        db.close
      end

      DB.open("duckdb://test.upd") do |db|
        row = db.query_one(
          "SELECT id, shape_type, shape_args, annotation FROM annotations WHERE id = 'a-1'",
          as: {String, String, String, String}
        )
        row[0].should eq("a-1")
        row[1].should eq("bbox")
        JSON.parse(row[2])["x"].as_i.should eq(0)
        JSON.parse(row[3])["label"].as_s.should eq("cat")
        db.close
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Show" do
    it "shows the correct annotation by id" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', '{\"label\":\"cat\"}', '{}')")
        db.exec("INSERT INTO annotations VALUES ('a-2', 'e-1', 'polygon', '{\"points\":[]}', '{\"label\":\"dog\"}', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("show", :pos, nil),
        Command::Argument.new("id", :optlong, "a-1"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        row = db.query_one(
          "SELECT id, shape_type FROM annotations WHERE id = 'a-1'",
          as: {String, String}
        )
        row[0].should eq("a-1")
        row[1].should eq("bbox")
        db.close
      end
    end

    it "does not return other annotations" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', '{\"label\":\"cat\"}', '{}')")
        db.exec("INSERT INTO annotations VALUES ('a-2', 'e-1', 'bbox', '{\"x\":10}', '{\"label\":\"dog\"}', '{}')")
        db.close
      end

      DB.open("duckdb://test.upd") do |db|
        rows = db.query_all("SELECT id FROM annotations WHERE id = 'a-1'", as: String)
        rows.size.should eq(1)
        db.close
      end
    end

    it "handles non-existent id gracefully without raising" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("show", :pos, nil),
        Command::Argument.new("id", :optlong, "nonexistent"),
      ]).run
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Delete" do
    it "deletes an existing annotation" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', '{\"label\":\"cat\"}', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("delete", :pos, nil),
        Command::Argument.new("id", :optlong, "a-1"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM annotations WHERE id = 'a-1'", as: Int64)
        count.should eq(0)
        db.close
      end
    end

    it "only deletes the target annotation" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', '{\"label\":\"cat\"}', '{}')")
        db.exec("INSERT INTO annotations VALUES ('a-2', 'e-1', 'bbox', '{\"x\":10}', '{\"label\":\"dog\"}', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("delete", :pos, nil),
        Command::Argument.new("id", :optlong, "a-1"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM annotations", as: Int64)
        count.should eq(1)
        remaining = db.query_one("SELECT id FROM annotations", as: String)
        remaining.should eq("a-2")
        db.close
      end
    end

    it "is a silent no-op when deleting a non-existent annotation" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("delete", :pos, nil),
        Command::Argument.new("id", :optlong, "nonexistent"),
      ]).run
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Update" do
    it "updates the shape_type" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', '{\"label\":\"cat\"}', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "a-1"),
        Command::Argument.new("type", :optlong, "polygon"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        shape_type = db.query_one("SELECT shape_type FROM annotations WHERE id = 'a-1'", as: String)
        shape_type.should eq("polygon")
        db.close
      end
    end

    it "updates the shape_args" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', '{\"label\":\"cat\"}', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "a-1"),
        Command::Argument.new("shape", :optlong, "{\"x\":10,\"y\":20,\"w\":50,\"h\":50}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        shape_args = JSON.parse(db.query_one("SELECT shape_args FROM annotations WHERE id = 'a-1'", as: String))
        shape_args["x"].as_i.should eq(10)
        shape_args["y"].as_i.should eq(20)
        db.close
      end
    end

    it "updates the annotation value" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', '{\"label\":\"cat\"}', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "a-1"),
        Command::Argument.new("annotation", :optlong, "{\"label\":\"dog\",\"score\":0.9}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        ann = JSON.parse(db.query_one("SELECT annotation FROM annotations WHERE id = 'a-1'", as: String))
        ann["label"].as_s.should eq("dog")
        ann["score"].as_f.should eq(0.9)
        db.close
      end
    end

    it "preserves unchanged fields when partially updating" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', '{\"label\":\"cat\"}', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "a-1"),
        Command::Argument.new("type", :optlong, "polygon"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        row = db.query_one(
          "SELECT shape_type, shape_args, annotation, entry_id FROM annotations WHERE id = 'a-1'",
          as: {String, String, String, String}
        )
        row[0].should eq("polygon")                        # updated
        JSON.parse(row[1])["x"].as_i.should eq(0)         # shape_args unchanged
        JSON.parse(row[2])["label"].as_s.should eq("cat") # annotation unchanged
        row[3].should eq("e-1")                           # entry_id unchanged
        db.close
      end
    end

    it "injects Updated-At and Updated-By into metadata" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', '{\"label\":\"cat\"}', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("annotation", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "a-1"),
        Command::Argument.new("type", :optlong, "polygon"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        metadata = JSON.parse(db.query_one("SELECT metadata FROM annotations WHERE id = 'a-1'", as: String))
        metadata["Updated-At"].as_s?.should_not be_nil
        metadata["Updated-By"].as_s.should eq("updcli")
        db.close
      end
    end

    it "raises when annotation not found" do
      expect_raises(Command::UpdError, /not found/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("annotation", :pos, nil),
          Command::Argument.new("update", :pos, nil),
          Command::Argument.new("id", :optlong, "nonexistent"),
          Command::Argument.new("type", :optlong, "polygon"),
        ]).run
      end
    end

    it "raises on invalid JSON in new shape" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', '{\"label\":\"cat\"}', '{}')")
        db.close
      end

      expect_raises(Command::UpdError, /Invalid JSON in new shape/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("annotation", :pos, nil),
          Command::Argument.new("update", :pos, nil),
          Command::Argument.new("id", :optlong, "a-1"),
          Command::Argument.new("shape", :optlong, "not valid json"),
        ]).run
      end
    end

    it "raises on invalid JSON in new annotation value" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', '{\"label\":\"cat\"}', '{}')")
        db.close
      end

      expect_raises(Command::UpdError, /Invalid JSON in new annotation/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("annotation", :pos, nil),
          Command::Argument.new("update", :pos, nil),
          Command::Argument.new("id", :optlong, "a-1"),
          Command::Argument.new("annotation", :optlong, "not valid json"),
        ]).run
      end
    end

    it "raises on invalid JSON in new metadata" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '{\"x\":0}', '{\"label\":\"cat\"}', '{}')")
        db.close
      end

      expect_raises(Command::UpdError, /Invalid JSON in new metadata/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("annotation", :pos, nil),
          Command::Argument.new("update", :pos, nil),
          Command::Argument.new("id", :optlong, "a-1"),
          Command::Argument.new("metadata", :optlong, "not valid json"),
        ]).run
      end
    end
  end
end
