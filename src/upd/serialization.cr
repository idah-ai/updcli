require "digest"
require "digest/sha256"
require "digest/sha512"
require "duckdb"
require "json"

module UPD
  module Serialization
    # RFC 5.4.1: Table order for data payload serialization
    # These tables MUST always be serialized in this exact order
    CORE_TABLES_ORDER = ["entries", "annotations"]

    # Validate table name to prevent SQL injection
    # Table names must only contain alphanumeric characters and underscores
    def self.validate_table_name(table_name : String)
      unless table_name.matches?(/^[a-zA-Z_][a-zA-Z0-9_]*$/)
        raise "Invalid table name: #{table_name}. Table names must start with a letter or underscore and contain only alphanumeric characters and underscores."
      end
    end

    # Canonical data type serialization per RFC Section 5.4.4
    def self.normalized_query_columns(columns)
      columns.map do |column|
        case column[:type]
        when "VARCHAR", "BLOB", "UUID"
          column[:name]
        when "BOOLEAN"
          column[:name]
        when "TINYINT", "SMALLINT", "INTEGER", "BIGINT", "HUGEINT",
             "UTINYINT", "USMALLINT", "UINTEGER", "UBIGINT"
          "CAST(#{column[:name]} AS VARCHAR)"
        when "FLOAT", "DOUBLE", "DECIMAL"
          "CAST(#{column[:name]} AS VARCHAR)"
        when "TIMESTAMP", "TIMESTAMPTZ"
          "strftime(#{column[:name]}, '%Y-%m-%dT%H:%M:%S.%fZ')"
        when "DATE"
          "strftime(#{column[:name]}, '%Y-%m-%d')"
        when "TIME", "TIMETZ"
          "strftime(#{column[:name]}, '%H:%M:%S.%f')"
        else
          raise "Unsupported column type: #{column[:name]} (#{column[:type]})"
        end
      end
    end

    # Read a column value and convert to canonical string representation
    def self.read_column(column, row)
      value = case column[:type]
              when "VARCHAR", "BLOB", "UUID"
                row.read(String?)
              when "BOOLEAN"
                bool_val = row.read(String?)
                bool_val ? (bool_val =~ /^t|true$/i ? "true" : "false") : nil
              when "TINYINT", "SMALLINT", "INTEGER", "BIGINT", "HUGEINT",
                   "UTINYINT", "USMALLINT", "UINTEGER", "UBIGINT",
                   "FLOAT", "DOUBLE", "DECIMAL",
                   "TIMESTAMP", "TIMESTAMPTZ", "DATE", "TIME", "TIMETZ"
                # Already cast to VARCHAR in the query
                row.read(String?)
              else
                raise "Unsupported column type: #{column[:name]} (#{column[:type]})"
              end

      # RFC 5.4.4: NULL values must be represented as \x00NULL\x00
      value || "\x00NULL\x00"
    end

    # Normalize SQL statement (remove comments, collapse whitespace)
    def self.normalize_sql(sql_statement : String) : String
      sql = sql_statement.gsub(/--.*/, "")
      sql = sql.gsub(/\/\*.*?\*\//m, "")
      sql = sql.gsub(/\s+/, " ")
      sql.strip
    end

    # Get table columns from information_schema (robust, handles complex CREATE statements)
    # Per RFC 5.4.3: Columns must be in ordinal_position order
    def self.get_table_columns(database, table_name : String)
      validate_table_name(table_name)

      database.query_all(
        "SELECT column_name, data_type FROM information_schema.columns WHERE table_name = ? ORDER BY ordinal_position ASC",
        table_name
      ) do |row|
        {
          name: row.read(String),
          type: row.read(String).upcase,
        }
      end
    end

    # Get WHERE clause for filtering table by dataset
    # Per RFC 5.4.1
    # Returns tuple of {clause, params} for safe parameterized queries
    def self.get_where_clause(table_name : String, dataset_id : String) : {String, Array(String)}
      case table_name
      when "entries"
        {"WHERE dataset_id = ?", [dataset_id]}
      when "annotations"
        # RFC 5.4.1: annotations filtered by entry_id IN (SELECT id FROM entries WHERE dataset_id = ...)
        {"WHERE entry_id IN (SELECT id FROM entries WHERE dataset_id = ?)", [dataset_id]}
      else
        # For flavor tables, assume they have dataset_id column
        # This should be validated or documented in the flavor spec
        {"WHERE dataset_id = ?", [dataset_id]}
      end
    end

    # Serialize a single table for a dataset
    # Returns the canonical byte stream per RFC Section 5.4
    def self.serialize_table(database, table_name : String, dataset_id : String, digest : Digest) : Nil
      validate_table_name(table_name)

      # Get columns from information_schema (guarantees correct ordinal order)
      columns = get_table_columns(database, table_name)

      query_columns = normalized_query_columns(columns)
      where_clause, where_params = get_where_clause(table_name, dataset_id)

      # Build query - table_name is validated above, safe to interpolate
      query = "SELECT #{query_columns.join(", ")} FROM #{table_name} #{where_clause} ORDER BY id ASC"

      first_row = true
      database.query(query, args: where_params) do |rs|
        i = 0
        rs.each do
          digest << "\x00ROW\x00" unless first_row

          columns.each_with_index do |column, index|
            digest << "\x00COL\x00" unless index == 0
            digest << read_column(column, rs)
          end

          first_row = false
          i += 1
        end
      end
    end

    # Compute data hash for a dataset
    # Per RFC Section 5.4
    # Supports multiple algorithms per RFC Section 9 Appendix A
    def self.compute_data_hash(database, dataset_id : String, tables_to_serialize : Array(String), algorithm : String = "SHA256") : String
      # Validate all table names first
      tables_to_serialize.each { |table_name| validate_table_name(table_name) }

      # Serialize each table (columns are fetched from information_schema inside serialize_table)
      # Hash the serialized data using specified algorithm
      digest = case algorithm
               when "SHA256"
                 Digest::SHA256.new
               when "SHA512"
                 Digest::SHA512.new
               else
                 raise "Unsupported hash algorithm: #{algorithm}. Supported: SHA256, SHA512"
               end

      tables_to_serialize.each_with_index do |table_name, index|
        digest << "\x00TABLE\x00" unless index == 0
        serialize_table(database, table_name, dataset_id, digest)
      end

      digest.hexfinal
    end

    # Compute schema hash
    # Per RFC Section 5.5
    # Supports multiple algorithms per RFC Section 9 Appendix A
    def self.compute_schema_hash(database, tables : Array(String), algorithm : String = "SHA256") : String
      # Validate all table names first
      tables.each { |table_name| validate_table_name(table_name) }

      # Get CREATE TABLE statements for all tables
      sql_create_stmts = tables.compact_map do |table_name|
        # table_name is validated above, safe to use in query
        database.query_one(
          "SELECT sql FROM duckdb_tables WHERE table_name = ?",
          table_name
        ) { |result| result.read(String) }
      end

      # Normalize, sort alphabetically by table name, and concatenate
      normalized_stmts = sql_create_stmts.map { |stmt| normalize_sql(stmt) }.sort!
      schema = normalized_stmts.join("\n")

      # Hash the schema using specified algorithm
      digest = case algorithm
               when "SHA256"
                 Digest::SHA256.new
               when "SHA512"
                 Digest::SHA512.new
               else
                 raise "Unsupported hash algorithm: #{algorithm}. Supported: SHA256, SHA512"
               end

      digest << schema
      digest.hexfinal
    end
  end
end
