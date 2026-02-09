require "digest/sha256"
require "base64"
require "openssl_ext"
require "json"

module Command
  class Verify < Base
    description "Verify dataset signatures"

    def run_impl
      datasets = root.database.query_all("SELECT id, metadata FROM datasets") do |dataset|
        [dataset.read(String), dataset.read(String)]
      end

      datasets.each do |(dataset_id, metadata)|
        metadata_json = begin
          JSON.parse(metadata).as_h
        rescue
          puts "Invalid JSON metadata for dataset #{dataset_id}"
          next
        end

        content_signatures = begin
          if sig = metadata_json["Content-Signature"]?
            sig.as_a
          else
            [] of JSON::Any
          end
        rescue
          [] of JSON::Any
        end

        if content_signatures.empty?
          puts "No signatures found for dataset #{dataset_id}"
          next
        end

        content_signatures.each do |sig|
          begin
            # Decode signature and certificate
            signature = Base64.decode(sig["signature"].as_s)
            certificate = OpenSSL::X509::Certificate.new(String.new(Base64.decode(sig["certificate"].as_s)))
            # certificate = OpenSSL::X509::Certificate.new(Base64.decode(sig["certificate"].as_s).to_s)
            public_key = certificate.public_key

            # Ensure the key is EC
            unless public_key.is_a?(OpenSSL::PKey::EC)
              raise "Public key is not an EC key for dataset #{dataset_id}"
            end
            ec_key = public_key.as(OpenSSL::PKey::EC)

            # Get signed flavor tables
            signed_flavor_tables = begin
              sig["signedFlavorTables"].as_a.map(&.as_s)
            rescue
              [] of String
            end

            # Regenerate data hash
            tables_to_serialize = ["entries", "annotations"] + signed_flavor_tables
            tables_serialization = tables_to_serialize.map do |table|
              sql_create_stmt = root.database.query_one(
                "SELECT sql FROM duckdb_tables WHERE table_name = '#{table}'"
              ) { |r| r.read(String) }
              unless sql_create_stmt
                raise "Missing CREATE TABLE statement for #{table}"
              end

              normalized_stmt = normalize_sql(sql_create_stmt)
              if match = /CREATE TABLE (\w+)\(([^)]+)/.match(normalized_stmt)
                columns = match[2].split(", ").map(&.strip).map do |column|
                  name, type, *rest = column.split(" ")
                  { name: name, type: type }
                end.compact

                query_columns = normalized_query_columns(columns)

                # Use correct WHERE clause based on table
                where_clause = case table
                when "entries"
                  "WHERE dataset_id = '#{dataset_id}'"
                when "annotations"
                  # Per RFC 5.4.1: annotations filtered by entry_id IN (SELECT id FROM entries WHERE dataset_id = ...)
                  "WHERE entry_id IN (SELECT id FROM entries WHERE dataset_id = '#{dataset_id}')"
                else
                  # For flavor tables, assume they have dataset_id column
                  # This should be validated or documented in the flavor spec
                  "WHERE dataset_id = '#{dataset_id}'"
                end

                root.database.query_all(
                  <<-EOF
                    SELECT #{query_columns.join(", ")} FROM #{table}
                    #{where_clause}
                    ORDER BY id ASC
                  EOF
                ) do |row|
                  columns.map do |column|
                    read_column(column, row)
                  end.join("\x00COL\x00")
                end.join("\x00ROW\x00")
              else
                raise "Failed to parse CREATE TABLE statement for #{table}"
              end
            end.join("\x00TABLE\x00")

            digest = Digest::SHA256.new
            digest.update(tables_serialization)
            dataHash = digest.hexfinal

            # Regenerate schema hash
            sql_create_stmts = tables_to_serialize.map do |table|
              root.database.query_one(
                "SELECT sql FROM duckdb_tables WHERE table_name = '#{table}'"
              ) { |r| r.read(String) }
            end.compact
            normalized_stmts = sql_create_stmts.map { |stmt| normalize_sql(stmt) }.sort
            schema = normalized_stmts.join("\n")
            schema_digest = Digest::SHA256.new
            schema_digest.update(schema)
            schemaHash = schema_digest.hexfinal

            # Verify data hash
            unless dataHash == sig["dataHash"].as_s
              raise "Data hash mismatch for dataset #{dataset_id}. Expected: #{sig["dataHash"].as_s}, Got: #{dataHash}"
            end

            # Verify schema hash
            unless schemaHash == sig["schemaHash"].as_s
              raise "Schema hash mismatch for dataset #{dataset_id}. Expected: #{sig["schemaHash"].as_s}, Got: #{schemaHash}"
            end

            # Verify signature
            unless ec_key.ec_verify(dataHash.hexbytes, signature)
              raise "Signature verification failed for dataset #{dataset_id}"
            end

            puts "✓ Signature for dataset #{dataset_id} is valid."
            puts "  - Data hash: #{dataHash}"
            puts "  - Signed at: #{sig["signedAt"].as_s}"
            puts "  - Algorithm: #{sig["dataHashAlgorithm"].as_s}"
            puts "  - Curve: #{sig["curve"].as_s}"
          rescue e
            puts "✗ Verification failed for dataset #{dataset_id}: #{e.message}"
          end
        end
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