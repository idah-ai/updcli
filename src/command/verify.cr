require "digest/sha256"
require "base64"
require "openssl_ext"
require "json"

require "./serialization"

module Command
  class Verify < Base
    description "Verify dataset ECDSA signatures"

    # Define CLI options
    option "dataset", "d", "Verify specific dataset ID (default: verify all)", type: :string
    option "verbose", "v", "Verbose output", type: :bool
    option "strict", "s", "Strict mode: also verify certificate validity dates", type: :bool

    def run_impl
      dataset_id = option("dataset")
      verbose = option("verbose") == "true"
      strict = option("strict") == "true"

      # Determine which datasets to verify
      datasets = if dataset_id && !dataset_id.empty?
        # Verify specific dataset
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
          puts "Error: Dataset not found: #{dataset_id}"
          exit 1
        end

        result
      else
        # Verify all datasets
        root.database.query_all("SELECT id, name, metadata FROM datasets") do |dataset|
          {
            id: dataset.read(String),
            name: dataset.read(String),
            metadata: dataset.read(String)
          }
        end
      end

      if datasets.empty?
        puts "No datasets found to verify"
        return
      end

      puts "Verifying #{datasets.size} dataset(s)..."
      puts ""

      total_datasets = 0
      total_signatures = 0
      failed_verifications = 0

      datasets.each do |dataset|
        total_datasets += 1
        dataset_id = dataset[:id]
        dataset_name = dataset[:name]
        metadata = dataset[:metadata]

        puts "Dataset: #{dataset_name} (#{dataset_id})"
        puts "-" * 80 if verbose

        metadata_json = begin
          JSON.parse(metadata).as_h
        rescue e
          puts "  ✗ Invalid JSON metadata: #{e.message}"
          failed_verifications += 1
          puts "" unless verbose
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
          puts "  - No signatures found"
          puts "" unless verbose
          next
        end

        puts "  Found #{content_signatures.size} signature(s)" if verbose

        content_signatures.each_with_index do |sig, idx|
          total_signatures += 1
          sig_num = content_signatures.size > 1 ? " ##{idx + 1}" : ""

          begin
            # Extract signature fields
            signature_b64 = sig["signature"].as_s
            certificate_b64 = sig["certificate"].as_s
            expected_data_hash = sig["dataHash"].as_s
            expected_schema_hash = sig["schemaHash"].as_s
            algorithm = sig["dataHashAlgorithm"].as_s
            curve = sig["curve"].as_s
            signed_at = sig["signedAt"].as_s

            # Get signed flavor tables
            signed_flavor_tables = begin
              sig["signedFlavorTables"].as_a.map(&.as_s)
            rescue
              [] of String
            end

            if verbose
              puts "  Signature#{sig_num}:"
              puts "    Signed at: #{signed_at}"
              puts "    Algorithm: #{algorithm}"
              puts "    Curve: #{curve}"
              puts "    Flavor tables: #{signed_flavor_tables.join(", ")}" if !signed_flavor_tables.empty?
            end

            # Verify algorithm
            unless algorithm == "SHA256"
              raise "Unsupported hash algorithm: #{algorithm} (only SHA256 is currently supported)"
            end

            # Verify curve
            unless curve == "secp256r1"
              raise "Unsupported ECDSA curve: #{curve} (only secp256r1 is currently supported)"
            end

            # Decode signature and certificate
            signature = Base64.decode(signature_b64)
            certificate = OpenSSL::X509::Certificate.new(String.new(Base64.decode(certificate_b64)))
            public_key = certificate.public_key

            # Ensure the key is EC
            unless public_key.is_a?(OpenSSL::PKey::EC)
              raise "Public key is not an EC key"
            end
            ec_key = public_key.as(OpenSSL::PKey::EC)

            if verbose
              puts "    Certificate subject: #{certificate.subject}"
              puts "    Certificate issuer: #{certificate.issuer}"
              puts "    Certificate valid: #{certificate.not_before} to #{certificate.not_after}"
            end

            # Per RFC 5.4.1: Use the standardized core table order
            tables_to_serialize = UPD::Serialization::CORE_TABLES_ORDER + signed_flavor_tables

            # Regenerate schema hash
            computed_schema_hash = UPD::Serialization.compute_schema_hash(
              root.database,
              tables_to_serialize
            )

            if verbose
              puts "    Expected schema hash: #{expected_schema_hash}"
              puts "    Computed schema hash: #{computed_schema_hash}"
            end

            # Verify schema hash
            unless computed_schema_hash == expected_schema_hash
              raise "Schema hash mismatch!\n" +
                    "    Expected: #{expected_schema_hash}\n" +
                    "    Computed: #{computed_schema_hash}"
            end

            # Regenerate data hash
            computed_data_hash = UPD::Serialization.compute_data_hash(
              root.database,
              dataset_id,
              tables_to_serialize
            )

            if verbose
              puts "    Expected data hash: #{expected_data_hash}"
              puts "    Computed data hash: #{computed_data_hash}"
            end

            # Verify data hash
            unless computed_data_hash == expected_data_hash
              raise "Data hash mismatch!\n" +
                    "    Expected: #{expected_data_hash}\n" +
                    "    Computed: #{computed_data_hash}"
            end

            # Verify ECDSA signature
            unless ec_key.ec_verify(computed_data_hash.hexbytes, signature)
              raise "ECDSA signature verification failed"
            end

            # Optional: Verify certificate validity
            if strict
              now = Time.utc
              if certificate.not_before > now
                raise "Certificate not yet valid (not_before: #{certificate.not_before})"
              end
              if certificate.not_after < now
                raise "Certificate expired (not_after: #{certificate.not_after})"
              end
            end

            puts "  ✓ Signature#{sig_num} valid"

          rescue e
            puts "  ✗ Signature#{sig_num} INVALID: #{e.message}"
            failed_verifications += 1
          end
        end

        puts "" unless verbose
      end

      # Summary
      puts "=" * 80
      puts "Verification Summary:"
      puts "  Datasets verified: #{total_datasets}"
      puts "  Total signatures: #{total_signatures}"
      puts "  Failed verifications: #{failed_verifications}"

      if failed_verifications > 0
        puts ""
        puts "⚠️  Some signatures failed verification!"
        exit 1
      else
        puts ""
        puts "✓ All signatures valid"
      end
    end
  end
end
