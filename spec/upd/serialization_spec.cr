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
    it "returns correct WHERE clause for entries table" do
      clause = UPD::Serialization.get_where_clause("entries", "dataset-123")
      clause.should eq("WHERE dataset_id = 'dataset-123'")
    end

    it "returns correct WHERE clause for annotations table" do
      clause = UPD::Serialization.get_where_clause("annotations", "dataset-123")
      clause.should eq("WHERE entry_id IN (SELECT id FROM entries WHERE dataset_id = 'dataset-123')")
    end

    it "returns default WHERE clause for flavor tables" do
      clause = UPD::Serialization.get_where_clause("custom_table", "dataset-123")
      clause.should eq("WHERE dataset_id = 'dataset-123'")
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
end
