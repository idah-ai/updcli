require "spec"
require "json"
require "duckdb"
require "digest/sha1"
require "mime"
require "file_utils"
require "../../../src/command/**"


# Helper: write a temp file with given content and yield its path
def with_temp_file(name : String, content : String, &)
  path = File.join(Dir.tempdir, name)
  File.write(path, content)
  begin
    yield path
  ensure
    File.delete(path) if File.exists?(path)
  end
end

def with_temp_file(name : String, content : Bytes, &)
  path = File.join(Dir.tempdir, name)
  File.open(path, "wb") { |f| f.write(content) }
  begin
    yield path
  ensure
    File.delete(path) if File.exists?(path)
  end
end


describe "Command::Media" do
  before_each do
    Command::Root.new([
      Command::Argument.new("input", :optlong, "test.upd"),
      Command::Argument.new("init", :pos, nil),
    ]).run
  end

  after_each do
    FileUtils.rm_rf("test.upd")
    # Clean up any extracted files left on disk
    Dir.glob("*.jpg").each { |f| File.delete(f) }
    Dir.glob("*.png").each { |f| File.delete(f) }
    Dir.glob("*.txt").each { |f| File.delete(f) }
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Create" do
    it "creates a media entry from a file" do
      with_temp_file("photo.jpg", "fake jpeg content") do |path|
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("create", :pos, nil),
          Command::Argument.new("file", :optlong, path),
        ]).run

        DB.open("duckdb://test.upd") do |db|
          count = db.query_one("SELECT COUNT(*) FROM medias", as: Int64)
          count.should eq(1)
          db.close
        end
      end
    end

    it "auto-generates id as SHA1(basename) + extension" do
      with_temp_file("photo.jpg", "fake jpeg content") do |path|
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("create", :pos, nil),
          Command::Argument.new("file", :optlong, path),
        ]).run

        expected_id = Digest::SHA1.hexdigest("photo") + ".jpg"

        DB.open("duckdb://test.upd") do |db|
          id = db.query_one("SELECT id FROM medias", as: String)
          id.should eq(expected_id)
          db.close
        end
      end
    end

    it "uses a custom id when provided" do
      with_temp_file("photo.jpg", "fake jpeg content") do |path|
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("create", :pos, nil),
          Command::Argument.new("id", :optlong, "my-custom-id"),
          Command::Argument.new("file", :optlong, path),
        ]).run

        DB.open("duckdb://test.upd") do |db|
          id = db.query_one("SELECT id FROM medias", as: String)
          id.should eq("my-custom-id")
          db.close
        end
      end
    end

    it "auto-detects MIME type from file extension" do
      with_temp_file("image.png", "fake png content") do |path|
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("create", :pos, nil),
          Command::Argument.new("file", :optlong, path),
        ]).run

        DB.open("duckdb://test.upd") do |db|
          media_type = db.query_one("SELECT media_type FROM medias", as: String)
          media_type.should eq(MIME.from_filename("image.png"))
          db.close
        end
      end
    end

    it "uses the provided MIME type instead of auto-detecting" do
      with_temp_file("data.bin", "raw bytes") do |path|
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("create", :pos, nil),
          Command::Argument.new("file", :optlong, path),
          Command::Argument.new("mimetype", :optlong, "application/octet-stream"),
        ]).run

        DB.open("duckdb://test.upd") do |db|
          media_type = db.query_one("SELECT media_type FROM medias", as: String)
          media_type.should eq("application/octet-stream")
          db.close
        end
      end
    end

    it "set MIME type to application/octet-stream when auto-detection fails and no MIME type provided" do
      with_temp_file("file.unknownext", "content") do |path|
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("create", :pos, nil),
          Command::Argument.new("file", :optlong, path),
        ]).run

        DB.open("duckdb://test.upd") do |db|
          media_type = db.query_one("SELECT media_type FROM medias", as: String)
          media_type.should eq("application/octet-stream")
          db.close
        end
      end
    end

    it "stores an empty key when none provided" do
      with_temp_file("photo.jpg", "fake jpeg content") do |path|
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("create", :pos, nil),
          Command::Argument.new("file", :optlong, path),
        ]).run

        DB.open("duckdb://test.upd") do |db|
          key = db.query_one("SELECT key FROM medias", as: String)
          key.should eq("")
          db.close
        end
      end
    end

    it "stores a custom key when provided" do
      with_temp_file("photo.jpg", "fake jpeg content") do |path|
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("create", :pos, nil),
          Command::Argument.new("file", :optlong, path),
          Command::Argument.new("key", :optlong, "thumbnail"),
        ]).run

        DB.open("duckdb://test.upd") do |db|
          key = db.query_one("SELECT key FROM medias", as: String)
          key.should eq("thumbnail")
          db.close
        end
      end
    end

    it "allows multiple variants of the same id with different keys (composite PK)" do
      with_temp_file("photo.jpg", "full size content") do |path_full|
        with_temp_file("photo_thumb.jpg", "thumb content") do |path_thumb|
          Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("media", :pos, nil),
            Command::Argument.new("create", :pos, nil),
            Command::Argument.new("id", :optlong, "photo-1"),
            Command::Argument.new("key", :optlong, "full"),
            Command::Argument.new("file", :optlong, path_full),
          ]).run

          Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("media", :pos, nil),
            Command::Argument.new("create", :pos, nil),
            Command::Argument.new("id", :optlong, "photo-1"),
            Command::Argument.new("key", :optlong, "thumbnail"),
            Command::Argument.new("file", :optlong, path_thumb),
          ]).run

          DB.open("duckdb://test.upd") do |db|
            count = db.query_one("SELECT COUNT(*) FROM medias WHERE id = 'photo-1'", as: Int64)
            count.should eq(2)
            db.close
          end
        end
      end
    end

    it "stores file content as blob" do
      content = "hello media content"
      with_temp_file("note.txt", content) do |path|
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("create", :pos, nil),
          Command::Argument.new("file", :optlong, path),
        ]).run

        DB.open("duckdb://test.upd") do |db|
          blob = db.query_one("SELECT blob_data FROM medias", as: Bytes)
          String.new(blob).should eq(content)
          db.close
        end
      end
    end

    it "injects default metadata when none provided" do
      with_temp_file("photo.jpg", "fake jpeg content") do |path|
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("create", :pos, nil),
          Command::Argument.new("file", :optlong, path),
        ]).run

        DB.open("duckdb://test.upd") do |db|
          metadata = JSON.parse(db.query_one("SELECT metadata FROM medias", as: String))
          metadata["Created-At"].as_s?.should_not be_nil
          metadata["Updated-At"].as_s?.should be_nil
          metadata["Created-by"].as_s.should eq("updcli")
          db.close
        end
      end
    end

    it "stores user-provided metadata as-is" do
      with_temp_file("photo.jpg", "fake jpeg content") do |path|
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("create", :pos, nil),
          Command::Argument.new("file", :optlong, path),
          Command::Argument.new("metadata", :optlong, "{\"source\": \"camera-1\"}"),
        ]).run

        DB.open("duckdb://test.upd") do |db|
          metadata = JSON.parse(db.query_one("SELECT metadata FROM medias", as: String))
          metadata["source"].as_s.should eq("camera-1")
          db.close
        end
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "List" do
    it "handles empty state gracefully" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("media", :pos, nil),
        Command::Argument.new("list", :pos, nil),
      ]).run
    end

    it "lists all media entries" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', '', NULL, 'image/jpeg', '{}')")
        db.exec("INSERT INTO medias VALUES ('m-2', '', NULL, 'image/png', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("media", :pos, nil),
        Command::Argument.new("list", :pos, nil),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM medias", as: Int64)
        count.should eq(2)
        db.close
      end
    end

    it "returns id and media_type fields" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', '', NULL, 'image/jpeg', '{}')")
        db.close
      end

      DB.open("duckdb://test.upd") do |db|
        row = db.query_one("SELECT id, media_type FROM medias WHERE id = 'm-1'", as: {String, String})
        row[0].should eq("m-1")
        row[1].should eq("image/jpeg")
        db.close
      end
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Show" do
    it "shows the correct media by id" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', '', NULL, 'image/jpeg', '{}')")
        db.exec("INSERT INTO medias VALUES ('m-2', '', NULL, 'image/png', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("media", :pos, nil),
        Command::Argument.new("show", :pos, nil),
        Command::Argument.new("id", :optlong, "m-1"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        row = db.query_one("SELECT id, media_type FROM medias WHERE id = 'm-1'", as: {String, String})
        row[0].should eq("m-1")
        row[1].should eq("image/jpeg")
        db.close
      end
    end

    it "does not return other media entries" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', '', NULL, 'image/jpeg', '{}')")
        db.exec("INSERT INTO medias VALUES ('m-2', '', NULL, 'image/png', '{}')")
        db.close
      end

      DB.open("duckdb://test.upd") do |db|
        rows = db.query_all("SELECT id FROM medias WHERE id = 'm-1'", as: String)
        rows.size.should eq(1)
        db.close
      end
    end

    it "handles non-existent id gracefully without raising" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("media", :pos, nil),
        Command::Argument.new("show", :pos, nil),
        Command::Argument.new("id", :optlong, "nonexistent"),
      ]).run
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Extract" do
    it "extracts blob to a file at the given output path" do
      content = "fake image bytes"
      output_path = File.join(Dir.tempdir, "extracted_output.jpg")

      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', '', ?, 'image/jpeg', '{}')", content.to_slice)
        db.close
      end

      begin
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("extract", :pos, nil),
          Command::Argument.new("id", :optlong, "m-1"),
          Command::Argument.new("output", :optlong, output_path),
        ]).run

        File.exists?(output_path).should be_true
        File.read(output_path).should eq(content)
      ensure
        File.delete(output_path) if File.exists?(output_path)
      end
    end

    it "uses the media id as default output filename when no output path given" do
      content = "fake image bytes"
      media_id = "m-1.jpg"

      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES (?, '', ?, 'image/jpeg', '{}')", media_id, content.to_slice)
        db.close
      end

      begin
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("extract", :pos, nil),
          Command::Argument.new("id", :optlong, media_id),
        ]).run

        File.exists?(media_id).should be_true
        File.read(media_id).should eq(content)
      ensure
        File.delete(media_id) if File.exists?(media_id)
      end
    end

    it "preserves binary content exactly during extract" do
      # Use actual binary data (not valid UTF-8)
      binary_content = Bytes[0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10] # JPEG magic bytes
      output_path = File.join(Dir.tempdir, "binary_output.jpg")

      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-bin', '', ?, 'image/jpeg', '{}')", binary_content)
        db.close
      end

      begin
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("extract", :pos, nil),
          Command::Argument.new("id", :optlong, "m-bin"),
          Command::Argument.new("output", :optlong, output_path),
        ]).run

        extracted = File.open(output_path, "rb") { |f| f.getb_to_end }
        extracted.should eq(binary_content)
      ensure
        File.delete(output_path) if File.exists?(output_path)
      end
    end

    it "handles non-existent id gracefully without raising" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("media", :pos, nil),
        Command::Argument.new("extract", :pos, nil),
        Command::Argument.new("id", :optlong, "nonexistent"),
      ]).run
    end
  end

  # ─────────────────────────────────────────────────────────────────────────────
  describe "Delete" do
    it "deletes an existing media" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', '', NULL, 'image/jpeg', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("media", :pos, nil),
        Command::Argument.new("delete", :pos, nil),
        Command::Argument.new("id", :optlong, "m-1"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM medias WHERE id = 'm-1'", as: Int64)
        count.should eq(0)
        db.close
      end
    end

    it "deletes all variants (keys) for a given id" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', 'full', NULL, 'image/jpeg', '{}')")
        db.exec("INSERT INTO medias VALUES ('m-1', 'thumbnail', NULL, 'image/jpeg', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("media", :pos, nil),
        Command::Argument.new("delete", :pos, nil),
        Command::Argument.new("id", :optlong, "m-1"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM medias WHERE id = 'm-1'", as: Int64)
        count.should eq(0)
        db.close
      end
    end

    it "only deletes the target media" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', '', NULL, 'image/jpeg', '{}')")
        db.exec("INSERT INTO medias VALUES ('m-2', '', NULL, 'image/png', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("media", :pos, nil),
        Command::Argument.new("delete", :pos, nil),
        Command::Argument.new("id", :optlong, "m-1"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        count = db.query_one("SELECT COUNT(*) FROM medias", as: Int64)
        count.should eq(1)
        remaining = db.query_one("SELECT id FROM medias", as: String)
        remaining.should eq("m-2")
        db.close
      end
    end

    it "is a silent no-op when deleting a non-existent media" do
      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("media", :pos, nil),
        Command::Argument.new("delete", :pos, nil),
        Command::Argument.new("id", :optlong, "nonexistent"),
      ]).run
    end
  end
  # ─────────────────────────────────────────────────────────────────────────────
  describe "Update" do
    it "updates the blob content from a new file" do
      with_temp_file("old.jpg", "old content") do |old_path|
        DB.open("duckdb://test.upd") do |db|
          db.exec("INSERT INTO medias VALUES ('m-1', '', ?, 'image/jpeg', '{}')", File.read(old_path).to_slice)
          db.close
        end

        with_temp_file("new.jpg", "new content") do |new_path|
          Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("media", :pos, nil),
            Command::Argument.new("update", :pos, nil),
            Command::Argument.new("id", :optlong, "m-1"),
            Command::Argument.new("key", :optlong, ""),
            Command::Argument.new("file", :optlong, new_path),
          ]).run

          DB.open("duckdb://test.upd") do |db|
            blob = db.query_one("SELECT blob_data FROM medias WHERE id = 'm-1'", as: Bytes)
            String.new(blob).should eq("new content")
            db.close
          end
        end
      end
    end

    it "updates the MIME type when a new file is provided" do
      with_temp_file("photo.jpg", "jpeg content") do |old_path|
        DB.open("duckdb://test.upd") do |db|
          db.exec("INSERT INTO medias VALUES ('m-1', '', ?, 'image/jpeg', '{}')", File.read(old_path).to_slice)
          db.close
        end

        with_temp_file("photo.png", "png content") do |new_path|
          Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("media", :pos, nil),
            Command::Argument.new("update", :pos, nil),
            Command::Argument.new("id", :optlong, "m-1"),
            Command::Argument.new("key", :optlong, ""),
            Command::Argument.new("file", :optlong, new_path),
          ]).run

          DB.open("duckdb://test.upd") do |db|
            media_type = db.query_one("SELECT media_type FROM medias WHERE id = 'm-1'", as: String)
            media_type.should eq(MIME.from_filename("photo.png"))
            db.close
          end
        end
      end
    end

    it "overrides auto-detected MIME type when mimetype is explicitly provided" do
      with_temp_file("data.jpg", "content") do |path|
        DB.open("duckdb://test.upd") do |db|
          db.exec("INSERT INTO medias VALUES ('m-1', '', ?, 'image/jpeg', '{}')", File.read(path).to_slice)
          db.close
        end

        with_temp_file("new.jpg", "new content") do |new_path|
          Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("media", :pos, nil),
            Command::Argument.new("update", :pos, nil),
            Command::Argument.new("id", :optlong, "m-1"),
            Command::Argument.new("key", :optlong, ""),
            Command::Argument.new("file", :optlong, new_path),
            Command::Argument.new("mimetype", :optlong, "application/octet-stream"),
          ]).run

          DB.open("duckdb://test.upd") do |db|
            media_type = db.query_one("SELECT media_type FROM medias WHERE id = 'm-1'", as: String)
            media_type.should eq("application/octet-stream")
            db.close
          end
        end
      end
    end

    it "set MIME type to application/octet-stream when auto-detection fails and no MIME type provided" do
      with_temp_file("file.unknownext", "content") do |path|
        DB.open("duckdb://test.upd") do |db|
          db.exec("INSERT INTO medias VALUES ('m-1', '', ?, 'application/octet-stream', '{}')", File.read(path).to_slice)
          db.close
        end

        with_temp_file("new.unknownext", "new content") do |new_path|
          Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("media", :pos, nil),
            Command::Argument.new("update", :pos, nil),
            Command::Argument.new("id", :optlong, "m-1"),
            Command::Argument.new("key", :optlong, ""),
            Command::Argument.new("file", :optlong, new_path),
          ]).run

          DB.open("duckdb://test.upd") do |db|
            media_type = db.query_one("SELECT media_type FROM medias WHERE id = 'm-1'", as: String)
            media_type.should eq("application/octet-stream")
            db.close
          end
        end
      end
    end

    it "updates only the specific key variant (composite PK)" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', 'full', ?, 'image/jpeg', '{}')", "full content".to_slice)
        db.exec("INSERT INTO medias VALUES ('m-1', 'thumbnail', ?, 'image/jpeg', '{}')", "thumb content".to_slice)
        db.close
      end

      with_temp_file("new_full.jpg", "updated full content") do |path|
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("update", :pos, nil),
          Command::Argument.new("id", :optlong, "m-1"),
          Command::Argument.new("key", :optlong, "full"),
          Command::Argument.new("file", :optlong, path),
        ]).run

        DB.open("duckdb://test.upd") do |db|
          full_blob = db.query_one("SELECT blob_data FROM medias WHERE id = 'm-1' AND key = 'full'", as: Bytes)
          thumb_blob = db.query_one("SELECT blob_data FROM medias WHERE id = 'm-1' AND key = 'thumbnail'", as: Bytes)
          String.new(full_blob).should eq("updated full content")
          String.new(thumb_blob).should eq("thumb content") # unchanged
          db.close
        end
      end
    end

    it "replaces metadata with newly provided metadata" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', '', NULL, 'image/jpeg', '{\"old_key\":\"old_val\"}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("media", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "m-1"),
        Command::Argument.new("key", :optlong, ""),
        Command::Argument.new("metadata", :optlong, "{\"new_key\":\"new_val\"}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        metadata = JSON.parse(db.query_one("SELECT metadata FROM medias WHERE id = 'm-1'", as: String))
        metadata["new_key"].as_s.should eq("new_val")
        metadata["old_key"]?.should be_nil
        db.close
      end
    end

    it "injects Updated-At and Updated-By into metadata" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', '', NULL, 'image/jpeg', '{}')")
        db.close
      end

      Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("media", :pos, nil),
        Command::Argument.new("update", :pos, nil),
        Command::Argument.new("id", :optlong, "m-1"),
        Command::Argument.new("key", :optlong, ""),
        Command::Argument.new("metadata", :optlong, "{\"source\":\"camera\"}"),
      ]).run

      DB.open("duckdb://test.upd") do |db|
        metadata = JSON.parse(db.query_one("SELECT metadata FROM medias WHERE id = 'm-1'", as: String))
        metadata["Updated-At"].as_s?.should_not be_nil
        metadata["Updated-By"].as_s.should eq("updcli")
        db.close
      end
    end

    it "raises when media id and key combination not found" do
      expect_raises(Command::UpdError, /not found/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("update", :pos, nil),
          Command::Argument.new("id", :optlong, "nonexistent"),
          Command::Argument.new("key", :optlong, ""),
          Command::Argument.new("metadata", :optlong, "{\"x\":1}"),
        ]).run
      end
    end

    it "raises when new file path does not exist" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', '', NULL, 'image/jpeg', '{}')")
        db.close
      end

      expect_raises(Command::UpdError, /File not found/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("update", :pos, nil),
          Command::Argument.new("id", :optlong, "m-1"),
          Command::Argument.new("key", :optlong, ""),
          Command::Argument.new("file", :optlong, "/nonexistent/path/file.jpg"),
        ]).run
      end
    end

    it "raises on invalid JSON in new metadata" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO medias VALUES ('m-1', '', NULL, 'image/jpeg', '{}')")
        db.close
      end

      expect_raises(Command::UpdError, /Invalid JSON in new metadata/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("media", :pos, nil),
          Command::Argument.new("update", :pos, nil),
          Command::Argument.new("id", :optlong, "m-1"),
          Command::Argument.new("key", :optlong, ""),
          Command::Argument.new("metadata", :optlong, "not valid json"),
        ]).run
      end
    end
  end
end
