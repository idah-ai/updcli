require "spec"
require "duckdb"
require "digest/sha256"
require "digest/sha512"
require "../../src/upd/serialization"

describe UPD::Serialization do
  describe ".normalize_sql" do
    it "removes single-line comments" do
      sql = "SELECT * FROM table -- this is a comment"
      result = UPD::Serialization.normalize_sql(sql)
      result.should eq("SELECT * FROM table")
    end

    it "removes multi-line comments" do
      sql = "SELECT * /* this is a\nmulti-line comment */ FROM table"
      result = UPD::Serialization.normalize_sql(sql)
      result.should eq("SELECT * FROM table")
    end

    it "collapses multiple whitespaces" do
      sql = "SELECT   *    FROM     table"
      result = UPD::Serialization.normalize_sql(sql)
      result.should eq("SELECT * FROM table")
    end

    it "trims leading and trailing whitespace" do
      sql = "  SELECT * FROM table  "
      result = UPD::Serialization.normalize_sql(sql)
      result.should eq("SELECT * FROM table")
    end

    it "handles complex SQL with comments and whitespace" do
      sql = <<-SQL
        CREATE TABLE test (
          -- Column definition
          id VARCHAR /* primary key */,
          name VARCHAR
        )
      SQL
      result = UPD::Serialization.normalize_sql(sql)
      result.should eq("CREATE TABLE test ( id VARCHAR , name VARCHAR )")
    end
  end

  describe ".normalized_query_columns" do
    it "handles VARCHAR columns" do
      columns = [{name: "name", type: "VARCHAR"}]
      result = UPD::Serialization.normalized_query_columns(columns)
      result.should eq(["name"])
    end

    it "handles BLOB columns" do
      columns = [{name: "data", type: "BLOB"}]
      result = UPD::Serialization.normalized_query_columns(columns)
      result.should eq(["data"])
    end

    it "handles UUID columns" do
      columns = [{name: "id", type: "UUID"}]
      result = UPD::Serialization.normalized_query_columns(columns)
      result.should eq(["id"])
    end

    it "casts INTEGER to VARCHAR" do
      columns = [{name: "count", type: "INTEGER"}]
      result = UPD::Serialization.normalized_query_columns(columns)
      result.should eq(["CAST(count AS VARCHAR)"])
    end

    it "casts BIGINT to VARCHAR" do
      columns = [{name: "big_num", type: "BIGINT"}]
      result = UPD::Serialization.normalized_query_columns(columns)
      result.should eq(["CAST(big_num AS VARCHAR)"])
    end

    it "casts FLOAT to VARCHAR" do
      columns = [{name: "price", type: "FLOAT"}]
      result = UPD::Serialization.normalized_query_columns(columns)
      result.should eq(["CAST(price AS VARCHAR)"])
    end

    it "casts DOUBLE to VARCHAR" do
      columns = [{name: "value", type: "DOUBLE"}]
      result = UPD::Serialization.normalized_query_columns(columns)
      result.should eq(["CAST(value AS VARCHAR)"])
    end

    it "formats TIMESTAMP columns" do
      columns = [{name: "created_at", type: "TIMESTAMP"}]
      result = UPD::Serialization.normalized_query_columns(columns)
      result.should eq(["strftime(created_at, '%Y-%m-%dT%H:%M:%S.%fZ')"])
    end

    it "formats DATE columns" do
      columns = [{name: "birth_date", type: "DATE"}]
      result = UPD::Serialization.normalized_query_columns(columns)
      result.should eq(["strftime(birth_date, '%Y-%m-%d')"])
    end

    it "formats TIME columns" do
      columns = [{name: "start_time", type: "TIME"}]
      result = UPD::Serialization.normalized_query_columns(columns)
      result.should eq(["strftime(start_time, '%H:%M:%S.%f')"])
    end

    it "raises error for unsupported types" do
      columns = [{name: "data", type: "UNKNOWN_TYPE"}]
      expect_raises(Exception, /Unsupported column type/) do
        UPD::Serialization.normalized_query_columns(columns)
      end
    end
  end

  describe ".get_where_clause" do
    it "returns correct WHERE clause and params for entries table" do
      clause, params = UPD::Serialization.get_where_clause("entries", "dataset-123")
      clause.should eq("WHERE dataset_id = ?")
      params.should eq(["dataset-123"])
    end

    it "returns correct WHERE clause and params for annotations table" do
      clause, params = UPD::Serialization.get_where_clause("annotations", "dataset-123")
      clause.should eq("WHERE entry_id IN (SELECT id FROM entries WHERE dataset_id = ?)")
      params.should eq(["dataset-123"])
    end

    it "returns default WHERE clause and params for flavor tables" do
      clause, params = UPD::Serialization.get_where_clause("custom_table", "dataset-123")
      clause.should eq("WHERE dataset_id = ?")
      params.should eq(["dataset-123"])
    end
  end

  describe "CORE_TABLES_ORDER" do
    it "has correct table order" do
      UPD::Serialization::CORE_TABLES_ORDER.should eq(["entries", "annotations"])
    end
  end

  describe "integration with DB" do
    it "computes data hash correctly" do
      # Create in-memory DB database
      DB.connect("duckdb::memory:") do |db|
        # Create schema
        db.exec(<<-SQL)
          CREATE TABLE datasets (
            id VARCHAR PRIMARY KEY,
            name VARCHAR,
            modality VARCHAR,
            metadata VARCHAR DEFAULT '{}'
          )
        SQL

        db.exec(<<-SQL)
          CREATE TABLE entries (
            id VARCHAR PRIMARY KEY,
            dataset_id VARCHAR,
            media_url VARCHAR,
            metadata VARCHAR DEFAULT '{}'
          )
        SQL

        db.exec(<<-SQL)
          CREATE TABLE annotations (
            id VARCHAR PRIMARY KEY,
            entry_id VARCHAR,
            shape_type VARCHAR,
            shape_args VARCHAR,
            annotation VARCHAR,
            metadata VARCHAR DEFAULT '{}'
          )
        SQL

        # Insert test data
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test Dataset', 'image', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'local:m-1', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-2', 'ds-1', 'local:m-2', '{}')")
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '[0,0,100,100]', '{\"label\":\"cat\"}', '{}')")
        db.exec("INSERT INTO annotations VALUES ('a-2', 'e-1', 'bbox', '[10,10,50,50]', '{\"label\":\"dog\"}', '{}')")

        # Compute hash
        hash = UPD::Serialization.compute_data_hash(db, "ds-1", ["entries", "annotations"], "SHA256")

        # Hash should be a 64-character hex string (SHA256)
        hash.should match(/^[a-f0-9]{64}$/)

        # Hash should be deterministic
        hash2 = UPD::Serialization.compute_data_hash(db, "ds-1", ["entries", "annotations"], "SHA256")
        hash.should eq(hash2)

        db.close
      end
    end

    it "computes different hashes for different data" do
      DB.connect("duckdb::memory:") do |db|
        # Create schema
        db.exec(<<-SQL)
          CREATE TABLE datasets (id VARCHAR PRIMARY KEY, name VARCHAR, modality VARCHAR, metadata VARCHAR DEFAULT '{}')
        SQL
        db.exec(<<-SQL)
          CREATE TABLE entries (id VARCHAR PRIMARY KEY, dataset_id VARCHAR, media_url VARCHAR, metadata VARCHAR DEFAULT '{}')
        SQL
        db.exec(<<-SQL)
          CREATE TABLE annotations (id VARCHAR PRIMARY KEY, entry_id VARCHAR, shape_type VARCHAR, shape_args VARCHAR, annotation VARCHAR, metadata VARCHAR DEFAULT '{}')
        SQL

        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test Dataset', 'image', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'local:m-1', '{}')")
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'bbox', '[0,0,100,100]', '{\"label\":\"cat\"}', '{}')")

        hash1 = UPD::Serialization.compute_data_hash(db, "ds-1", ["entries", "annotations"], "SHA256")

        # Modify data
        db.exec("UPDATE annotations SET annotation = '{\"label\":\"dog\"}' WHERE id = 'a-1'")

        hash2 = UPD::Serialization.compute_data_hash(db, "ds-1", ["entries", "annotations"], "SHA256")

        hash1.should_not eq(hash2)

        db.close
      end
    end

    it "computes schema hash correctly" do
      DB.connect("duckdb::memory:") do |db|
        db.exec(<<-SQL)
          CREATE TABLE entries (
            id VARCHAR PRIMARY KEY,
            dataset_id VARCHAR,
            media_url VARCHAR,
            metadata VARCHAR DEFAULT '{}'
          )
        SQL

        db.exec(<<-SQL)
          CREATE TABLE annotations (
            id VARCHAR PRIMARY KEY,
            entry_id VARCHAR,
            shape_type VARCHAR,
            shape_args VARCHAR,
            annotation VARCHAR,
            metadata VARCHAR DEFAULT '{}'
          )
        SQL

        hash = UPD::Serialization.compute_schema_hash(db, ["entries", "annotations"], "SHA256")

        # Hash should be a 64-character hex string
        hash.should match(/^[a-f0-9]{64}$/)

        # Hash should be deterministic
        hash2 = UPD::Serialization.compute_schema_hash(db, ["entries", "annotations"], "SHA256")
        hash.should eq(hash2)

        db.close
      end
    end

    it "computes different schema hashes for different schemas" do
      db =  DB.connect("duckdb::memory:") do |db|
        db.exec("CREATE TABLE entries (id VARCHAR PRIMARY KEY)")
        db.exec("CREATE TABLE annotations (id VARCHAR PRIMARY KEY)")

        hash1 = UPD::Serialization.compute_schema_hash(db, ["entries", "annotations"], "SHA256")

        # Create different schema
        DB.connect("duckdb::memory:") do |db2|
          db2.exec("CREATE TABLE entries (id VARCHAR PRIMARY KEY, extra_col VARCHAR)")
          db2.exec("CREATE TABLE annotations (id VARCHAR PRIMARY KEY)")

          hash2 = UPD::Serialization.compute_schema_hash(db2, ["entries", "annotations"], "SHA256")

          hash1.should_not eq(hash2)

          db.close
          db2.close
        end
      end
    end

    it "supports SHA512 hash algorithm" do
      DB.connect("duckdb::memory:") do |db|
        db.exec("CREATE TABLE datasets (id VARCHAR PRIMARY KEY, name VARCHAR, modality VARCHAR, metadata VARCHAR DEFAULT '{}')")
        db.exec("CREATE TABLE entries (id VARCHAR PRIMARY KEY, dataset_id VARCHAR, media_url VARCHAR, metadata VARCHAR DEFAULT '{}')")
        db.exec("CREATE TABLE annotations (id VARCHAR PRIMARY KEY, entry_id VARCHAR, shape_type VARCHAR, shape_args VARCHAR, annotation VARCHAR, metadata VARCHAR DEFAULT '{}')")

        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test', 'image', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'local:m-1', '{}')")

        hash = UPD::Serialization.compute_data_hash(db, "ds-1", ["entries", "annotations"], "SHA512")

        # SHA512 produces 128-character hex string
        hash.should match(/^[a-f0-9]{128}$/)

        db.close
      end
    end

    it "raises error for unsupported hash algorithm" do
      DB.connect("duckdb::memory:") do |db|
        db.exec("CREATE TABLE entries (id VARCHAR PRIMARY KEY)")

        expect_raises(Exception, /Unsupported hash algorithm/) do
          UPD::Serialization.compute_data_hash(db, "ds-1", ["entries"], "MD5")
        end

        db.close
      end
    end
  end

  describe ".serialize_table" do
    it "serializes table rows with correct delimiters" do
      DB.connect("duckdb::memory:") do |db|
        db.exec("CREATE TABLE entries (id VARCHAR PRIMARY KEY, dataset_id VARCHAR, media_url VARCHAR, metadata VARCHAR)")
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'url1', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-2', 'ds-1', 'url2', '{}')")

        result = UPD::Serialization.serialize_table(db, "entries", "ds-1")

        # Should contain row delimiter
        result.should contain("\x00ROW\x00")

        # Should contain column delimiter
        result.should contain("\x00COL\x00")

        db.close
      end
    end

    it "orders rows by id" do
      DB.connect("duckdb::memory:") do |db|
        db.exec("CREATE TABLE entries (id VARCHAR PRIMARY KEY, dataset_id VARCHAR, media_url VARCHAR, metadata VARCHAR)")
        # Insert in reverse order
        db.exec("INSERT INTO entries VALUES ('e-2', 'ds-1', 'url2', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'url1', '{}')")

        result1 = UPD::Serialization.serialize_table(db, "entries", "ds-1")

        # The result should always be the same regardless of insertion order
        DB.connect("duckdb::memory:") do |db2|
          db2.exec("CREATE TABLE entries (id VARCHAR PRIMARY KEY, dataset_id VARCHAR, media_url VARCHAR, metadata VARCHAR)")
          db2.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'url1', '{}')")
          db2.exec("INSERT INTO entries VALUES ('e-2', 'ds-1', 'url2', '{}')")

          result2 = UPD::Serialization.serialize_table(db2, "entries", "ds-1")

          result1.should eq(result2)

          db.close
          db2.close
        end
      end
    end
  end

  describe "SQL injection prevention" do
    it "validates table names and rejects SQL injection attempts" do
      expect_raises(Exception, /Invalid table name/) do
        UPD::Serialization.validate_table_name("users; DROP TABLE users--")
      end

      expect_raises(Exception, /Invalid table name/) do
        UPD::Serialization.validate_table_name("users' OR '1'='1")
      end

      expect_raises(Exception, /Invalid table name/) do
        UPD::Serialization.validate_table_name("users/**/UNION/**/SELECT")
      end
    end

    it "accepts valid table names" do
      # Should not raise
      UPD::Serialization.validate_table_name("entries")
      UPD::Serialization.validate_table_name("custom_table_123")
      UPD::Serialization.validate_table_name("_private_table")
      UPD::Serialization.validate_table_name("CamelCaseTable")
    end

    it "prevents SQL injection in dataset_id via parameterized queries" do
      DB.connect("duckdb::memory:") do |db|
        db.exec("CREATE TABLE entries (id VARCHAR PRIMARY KEY, dataset_id VARCHAR, media_url VARCHAR, metadata VARCHAR)")
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'url1', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-2', 'ds-malicious', 'url2', '{}')")

        # Attempt SQL injection in dataset_id
        malicious_id = "ds-1' OR '1'='1"

        # Should return empty result (no match), not all rows
        result = UPD::Serialization.serialize_table(db, "entries", malicious_id)

        # Should be empty (no COL delimiter means no data)
        result.should_not contain("\x00COL\x00")

        db.close
      end
    end
  end

  describe "RFC 5.4 compliance - Exact hash values" do
    it "produces exact hash specified in RFC example (data hash)" do
      DB.connect("duckdb::memory:") do |db|
        # Create exact schema from RFC
        db.exec(<<-SQL)
          CREATE TABLE entries (
            id VARCHAR PRIMARY KEY,
            dataset_id VARCHAR,
            media_url VARCHAR,
            metadata VARCHAR
          )
        SQL

        db.exec(<<-SQL)
          CREATE TABLE annotations (
            id VARCHAR PRIMARY KEY,
            entry_id VARCHAR,
            shape_type VARCHAR,
            shape_args VARCHAR,
            annotation VARCHAR,
            metadata VARCHAR
          )
        SQL

        # Insert exact data from RFC 5.4.6 example
        db.exec("INSERT INTO entries VALUES ('e-001', 'ds-001', 'https://example.com/img.jpg', '{\"cby\":\"alice\"}')")
        db.exec("INSERT INTO entries VALUES ('e-002', 'ds-001', 'local:m-002', '{\"cby\":\"bob\"}')")
        db.exec("INSERT INTO annotations VALUES ('a-001', 'e-001', 'box', '{\"x\":0}', '{\"class\":\"cat\"}', '{}')")

        # Compute hash
        hash = UPD::Serialization.compute_data_hash(db, "ds-001", ["entries", "annotations"], "SHA256")

        # Expected serialization per RFC:
        # e-001\x00COL\x00ds-001\x00COL\x00https://example.com/img.jpg\x00COL\x00{"cby":"alice"}\x00ROW\x00e-002\x00COL\x00ds-001\x00COL\x00local:m-002\x00COL\x00{"cby":"bob"}\x00TABLE\x00a-001\x00COL\x00e-001\x00COL\x00box\x00COL\x00{"x":0}\x00COL\x00{"class":"cat"}\x00COL\x00{}

        expected_serialization = "e-001\x00COL\x00ds-001\x00COL\x00https://example.com/img.jpg\x00COL\x00{\"cby\":\"alice\"}\x00ROW\x00e-002\x00COL\x00ds-001\x00COL\x00local:m-002\x00COL\x00{\"cby\":\"bob\"}\x00TABLE\x00a-001\x00COL\x00e-001\x00COL\x00box\x00COL\x00{\"x\":0}\x00COL\x00{\"class\":\"cat\"}\x00COL\x00{}"
        expected_hash = Digest::SHA256.hexdigest(expected_serialization)

        hash.should eq(expected_hash)

        db.close
      end
    end

    it "produces deterministic hash for NULL values per RFC 5.4.4" do
      DB.connect("duckdb::memory:") do |db|
        db.exec("CREATE TABLE entries (id VARCHAR PRIMARY KEY, dataset_id VARCHAR, media_url VARCHAR, metadata VARCHAR)")

        # Insert row with NULL metadata
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'url1', NULL)")

        serialized = UPD::Serialization.serialize_table(db, "entries", "ds-1")

        # Per RFC: NULL must be represented as \x00NULL\x00
        serialized.should contain("\x00NULL\x00")

        # Verify exact serialization
        # Expected: e-1\x00COL\x00ds-1\x00COL\x00url1\x00COL\x00\x00NULL\x00
        serialized.should eq("e-1\x00COL\x00ds-1\x00COL\x00url1\x00COL\x00\x00NULL\x00")

        db.close
      end
    end

    it "serializes rows in ascending ID order per RFC 5.4.2" do
      DB.connect("duckdb::memory:") do |db|
        db.exec("CREATE TABLE entries (id VARCHAR PRIMARY KEY, dataset_id VARCHAR, media_url VARCHAR, metadata VARCHAR)")

        # Insert in random order
        db.exec("INSERT INTO entries VALUES ('e-3', 'ds-1', 'url3', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'url1', '{}')")
        db.exec("INSERT INTO entries VALUES ('e-2', 'ds-1', 'url2', '{}')")

        serialized = UPD::Serialization.serialize_table(db, "entries", "ds-1")

        # Should always be sorted by ID: e-1, e-2, e-3
        rows = serialized.split("\x00ROW\x00")
        rows[0].should start_with("e-1\x00COL\x00")
        rows[1].should start_with("e-2\x00COL\x00")
        rows[2].should start_with("e-3\x00COL\x00")

        db.close
      end
    end

    it "serializes columns in ordinal position order per RFC 5.4.3" do
      DB.connect("duckdb::memory:") do |db|
        db.exec(<<-SQL)
          CREATE TABLE test_table (
            third_col VARCHAR,
            id VARCHAR PRIMARY KEY,
            second_col VARCHAR,
            dataset_id VARCHAR,
            first_col VARCHAR
          )
        SQL

        db.exec("INSERT INTO test_table VALUES ('c', 't-1', 'b', 'ds-1', 'a')")

        columns = UPD::Serialization.get_table_columns(db, "test_table")

        # Columns should be in CREATE TABLE order, not alphabetical
        columns.map { |c| c[:name] }.should eq(["third_col", "id", "second_col", "dataset_id", "first_col"])

        serialized = UPD::Serialization.serialize_table(db, "test_table", "ds-1")

        # Should be in ordinal order: third_col, id, second_col, dataset_id, first_col
        serialized.should eq("c\x00COL\x00t-1\x00COL\x00b\x00COL\x00ds-1\x00COL\x00a")

        db.close
      end
    end

    it "uses correct table order per RFC 5.4.1" do
      DB.connect("duckdb::memory:") do |db|
        db.exec("CREATE TABLE entries (id VARCHAR PRIMARY KEY, dataset_id VARCHAR, media_url VARCHAR, metadata VARCHAR)")
        db.exec("CREATE TABLE annotations (id VARCHAR PRIMARY KEY, entry_id VARCHAR, shape_type VARCHAR, shape_args VARCHAR, annotation VARCHAR, metadata VARCHAR)")

        db.exec("INSERT INTO entries VALUES ('e-1', 'ds-1', 'url', '{}')")
        db.exec("INSERT INTO annotations VALUES ('a-1', 'e-1', 'box', '{}', '{}', '{}')")

        hash = UPD::Serialization.compute_data_hash(db, "ds-1", ["entries", "annotations"], "SHA256")

        # If we reverse the order, hash should be different
        hash_reversed = UPD::Serialization.compute_data_hash(db, "ds-1", ["annotations", "entries"], "SHA256")

        hash.should_not eq(hash_reversed)

        db.close
      end
    end

    it "produces exact schema hash per RFC 5.5" do
      DB.connect("duckdb::memory:") do |db|
        # Create tables with exact RFC schema (simplified for testing)
        db.exec("CREATE TABLE entries (id VARCHAR PRIMARY KEY, dataset_id VARCHAR)")
        db.exec("CREATE TABLE annotations (id VARCHAR PRIMARY KEY, entry_id VARCHAR)")

        schema_hash = UPD::Serialization.compute_schema_hash(db, ["entries", "annotations"], "SHA256")

        # Get normalized CREATE statements
        entries_sql = db.query_one("SELECT sql FROM duckdb_tables WHERE table_name = 'entries'") { |r| r.read(String) }
        annotations_sql = db.query_one("SELECT sql FROM duckdb_tables WHERE table_name = 'annotations'") { |r| r.read(String) }

        # Normalize
        entries_normalized = UPD::Serialization.normalize_sql(entries_sql)
        annotations_normalized = UPD::Serialization.normalize_sql(annotations_sql)

        # Sort alphabetically: annotations before entries
        sorted_stmts = [annotations_normalized, entries_normalized].sort
        expected_schema = sorted_stmts.join("\n")
        expected_hash = Digest::SHA256.hexdigest(expected_schema)

        schema_hash.should eq(expected_hash)

        db.close
      end
    end
  end
end