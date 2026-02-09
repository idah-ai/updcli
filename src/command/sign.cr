require "digest/sha256"
require "base64"
require "openssl_ext"
require "json"
require "time"

require "./dataset/update"

module Command
  record Signature,
    signature : String,
    dataHashAlgorithm : String,
    dataHash : String,
    schemaHash : String,
    certificate : String,
    curve : String,
    signedAt : String,
    signedFlavorTables : Array(String) do
      include JSON::Serializable

      def to_h
        {
          "signature" => signature,
          "dataHashAlgorithm" => dataHashAlgorithm,
          "dataHash" => dataHash,
          "schemaHash" => schemaHash,
          "certificate" => certificate,
          "curve" => curve,
          "signedAt" => signedAt,
          "signedFlavorTables" => signedFlavorTables
        }
      end
    end

  class Sign < Base
    description "Sign datasets"

    def run_impl
      # Get CREATE TABLE statements for core tables
      sql_create_stmt = root.database.query_all(
        <<-EOF
          SELECT sql FROM duckdb_tables
          WHERE table_name IN ('annotations', 'entries')
          ORDER BY table_name ASC
        EOF
      ) do |table|
        table.read(String)
      end

      if sql_create_stmt.empty?
        puts "No tables found."
        return
      end

      # Normalize and sort CREATE TABLE statements
      normalized_stmt = sql_create_stmt.map { |stmt| normalize_sql(stmt) }
      schema = normalized_stmt.sort.join("\n")
      digest = Digest::SHA256.new
      digest.update(schema)
      schemaHash = digest.hexfinal

      # Extract table columns for serialization
      tables_columns = normalized_stmt.map do |stmt|
        if match = /CREATE TABLE (\w+)\(([^)]+)/.match(stmt)
          {
            name: match[1],
            columns: match[2].split(", ").map(&.strip).map do |column|
              name, type, *rest = column.split(" ")
              { name: name, type: type }
            end.compact
          }
        else
          puts "Failed to parse CREATE TABLE statement: #{stmt}"
          nil
        end
      end.compact

      datasets = root.database.query_all("SELECT id, metadata FROM datasets") do |dataset|
        [dataset.read(String), dataset.read(String)]
      end

      datasets.each do |(dataset_id, metadata)|
        tables_to_serialize = ["entries", "annotations"]
        tables_serialization = tables_to_serialize.map do |table|
          table_columns = tables_columns.find { |tc| tc[:name] == table }
          unless table_columns
            raise "Missing table #{table}"
          end

          query_columns = normalized_query_columns(table_columns[:columns])

          # Use correct WHERE clause based on table
          where_clause = case table
          when "entries"
            "WHERE dataset_id = '#{dataset_id}'"
          when "annotations"
            # Per RFC 5.4.1: annotations filtered by entry_id IN (SELECT id FROM entries WHERE dataset_id = ...)
            "WHERE entry_id IN (SELECT id FROM entries WHERE dataset_id = '#{dataset_id}')"
          else
            raise "Unknown table: #{table}"
          end

          root.database.query_all(
            <<-EOF
              SELECT #{query_columns.join(", ")} FROM #{table}
              #{where_clause}
              ORDER BY id ASC
            EOF
          ) do |row|
            table_columns[:columns].map do |column|
              read_column(column, row)
            end.join("\x00COL\x00")
          end.join("\x00ROW\x00")
        end.join("\x00TABLE\x00")

        # Hash the data
        digest = Digest::SHA256.new
        digest.update(tables_serialization)
        dataHash = digest.hexfinal

        # Read key and certificate
        key_pem = File.read("ec_private.key")
        cert_pem = File.read("ec_certificate.pem")

        # Create objects
        ec_key = OpenSSL::PKey::EC.new(key_pem)
        certificate = OpenSSL::X509::Certificate.new(cert_pem)

        # Sign the raw data hash bytes
        signature = ec_key.ec_sign(dataHash.hexbytes)

        # Parse existing metadata
        metadata_json = begin
          JSON.parse(metadata).as_h
        rescue
          {} of String => JSON::Any
        end

        # Get existing signatures as Array(JSON::Any)
        content_signatures = begin
          if existing = metadata_json["Content-Signature"]?
            existing.as_a
          else
            [] of JSON::Any
          end
        rescue
          [] of JSON::Any
        end

        # Create new signature object
        new_signature = Signature.new(
          Base64.strict_encode(signature),
          "SHA256",
          dataHash,
          schemaHash,
          Base64.strict_encode(certificate.to_pem),
          "secp256r1",
          Time.utc.to_rfc3339,
          [] of String
        )

        # Append new signature as JSON::Any
        content_signatures << JSON.parse(new_signature.to_json)

        # Update metadata
        metadata_json["Content-Signature"] = JSON::Any.new(content_signatures)

        puts Dataset::Update.for([
          Argument.new("id", :optlong, dataset_id),
          Argument.new("metadata", :optlong, metadata_json.to_json)
        ], root).run
      end
    end

    private def normalized_query_columns(columns)
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
          raise "Unsupported attribute #{column[:name]} type #{column[:type]}"
        end
      end
    end

    private def read_column(column, row)
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
        raise "Unsupported attribute #{column[:name]} type #{column[:type]}"
      end

      value || "\x00NULL\x00"
    end

    private def normalize_sql(sql_statement : String) : String
      sql = sql_statement.gsub(/--.*/, "")
      sql = sql.gsub(/\/\*.*?\*\//m, "")
      sql = sql.gsub(/\s+/, " ")
      sql.strip
    end
  end
end