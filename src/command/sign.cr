require "digest/sha256"
require "digest/sha512"
require "base64"
require "openssl_ext"
require "json"
require "time"

require "./dataset/update"
require "../upd/serialization"

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
    Log = ::Log.for("sign")

    description "Sign datasets with ECDSA signatures"

    # Define CLI options
    option "key", "k", "Path to EC private key", required: true, type: :string
    option "cert", "c", "Path to X.509 certificate", required: true, type: :string
    option "dataset", "d", "Sign specific dataset ID (default: sign all)", type: :string
    option "flavor-tables", "f", "Comma-separated list of flavor tables to include", type: :string
    option "algorithm", "a", "Hash algorithm: SHA256, SHA512", default: "SHA256", type: :string
    option "curve", "u", "ECDSA curve: secp256r1", default: "secp256r1", type: :string
    option "verbose", "v", "Verbose output", type: :bool

    def run_impl
      key_path = option("key")
      cert_path = option("cert")
      dataset_id = option("dataset")
      flavor_tables_str = option("flavor-tables")
      algorithm = (option("algorithm") || "SHA256").upcase
      curve = option("curve") || "secp256r1"
      verbose = option("verbose") == "true"

      # Validate algorithm
      unless ["SHA256", "SHA512"].includes?(algorithm)
        raise Command::UpdError.new(
          "Unsupported hash algorithm: #{algorithm}\n" +
          "Supported algorithms: SHA256, SHA512\n" +
          "See RFC Section 9 Appendix A for recommendations",
          self
        )
      end

      # Validate curve
      unless ["secp256r1"].includes?(curve)
        raise Command::UpdError.new(
          "Unsupported ECDSA curve: #{curve}\n" +
          "Supported curves: secp256r1\n" +
          "See RFC Section 9 Appendix A for recommendations",
          self
        )
      end

      # Parse flavor tables
      flavor_tables = if flavor_tables_str && !flavor_tables_str.empty?
        flavor_tables_str.split(",").map(&.strip)
      else
        [] of String
      end

      # Validate required files
      unless key_path && File.exists?(key_path)
        raise Command::UpdError.new(
          "Private key file not found: #{key_path}\n" +
          "Generate one with: openssl ecparam -name prime256v1 -genkey -noout -out key.pem",
          self
        )
      end

      unless cert_path && File.exists?(cert_path)
        raise Command::UpdError.new(
          "Certificate file not found: #{cert_path}\n" +
          "Generate one with: openssl req -new -x509 -key #{key_path} -out cert.pem -days 365",
          self
        )
      end

      # Read key and certificate
      key_pem = File.read(key_path)
      cert_pem = File.read(cert_path)
      ec_key = OpenSSL::PKey::EC.new(key_pem)
      certificate = OpenSSL::X509::Certificate.new(cert_pem)

      if verbose
        Log.info {"Using private key: #{key_path}"}
        Log.info {"Using certificate: #{cert_path}"}
        Log.info {"Hash algorithm: #{algorithm}"}
        Log.info {"ECDSA curve: #{curve}"}
        Log.info {"Certificate subject: #{certificate.subject}"}
        Log.info {"Certificate valid from #{certificate.not_before} to #{certificate.not_after}"}
      end

      # Determine which datasets to sign
      datasets = if dataset_id && !dataset_id.empty?
        # Sign specific dataset
        result = root.database.query_all(
          "SELECT id, name, metadata FROM datasets WHERE id = ?",
          dataset_id
        ) do |dataset|
          {
            id: dataset.read(String),
            name: dataset.read(String),
            metadata: dataset.read(String)
          }
        end

        if result.empty?
          raise Command::UpdError.new("Dataset not found: #{dataset_id}", self)
        end

        result
      else
        # Sign all datasets
        root.database.query_all("SELECT id, name, metadata FROM datasets") do |dataset|
          {
            id: dataset.read(String),
            name: dataset.read(String),
            metadata: dataset.read(String)
          }
        end
      end

      if datasets.empty?
        Log.warn {"No datasets found to sign"}
        return
      end

      # Compute schema hash once (same for all datasets unless they have different flavor tables)
      # Per RFC 5.4.1: Use the standardized core table order
      all_tables = UPD::Serialization::CORE_TABLES_ORDER + flavor_tables

      if verbose
        Log.info {"Tables included in signature: #{all_tables.join(", ")}"}
      end

      schemaHash = UPD::Serialization.compute_schema_hash(root.database, all_tables, algorithm)

      if verbose
        Log.info { "Schema hash: #{schemaHash}" }
        Log.info { "" }
      end

      Log.info { "Signing #{datasets.size} dataset(s)..." }
      Log.info { "" }

      datasets.each do |dataset|
        dataset_id = dataset[:id]
        dataset_name = dataset[:name]
        metadata = dataset[:metadata]

        Log.info { "Processing: #{dataset_name} (#{dataset_id})"}

        # Compute data hash
        dataHash = UPD::Serialization.compute_data_hash(root.database, dataset_id, all_tables, algorithm)
        Log.info { "  Data hash: #{dataHash}" if verbose}

        # Sign the data hash
        signature = ec_key.ec_sign(dataHash.hexbytes)
        Log.info { "  Signature: #{signature.size} bytes" } if verbose

        # Parse existing metadata
        metadata_json = begin
          JSON.parse(metadata).as_h
        rescue
          {} of String => JSON::Any
        end

        # Get existing signatures
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
          algorithm,
          dataHash,
          schemaHash,
          Base64.strict_encode(certificate.to_pem),
          curve,
          Time.utc.to_rfc3339,
          flavor_tables
        )

        # Append new signature
        content_signatures << JSON.parse(new_signature.to_json)
        metadata_json["Content-Signature"] = JSON::Any.new(content_signatures)

        # Update dataset metadata
        result = Dataset::Update.for([
          Argument.new("id", :optlong, dataset_id),
          Argument.new("metadata", :optlong, metadata_json.to_json)
        ], root).run

        Log.info { "  ✓ Signed successfully (#{content_signatures.size} total signature(s))" }
      end

      Log.info { "" }
      Log.info { "Signing complete!" }
    end
  end
end
