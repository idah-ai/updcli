require "digest/sha256"
require "digest/sha512"
require "base64"
require "openssl_ext"
require "json"

require "./base"
require "../upd/serialization"
require "../upd/signature_validator"

module Command
  class Verify < Base
    Log = ::Log.for("verify")

    description "Verify dataset ECDSA signatures"

    # Define CLI options
    option "dataset", "d", "Verify specific dataset ID (default: verify all)", type: :string
    option "verbose", "v", "Verbose output", type: :bool
    option "strict", "s", "Strict mode: also verify certificate validity dates", type: :bool

    # Summary statistics for verification run
    record VerificationSummary,
      total_datasets : Int32,
      total_signatures : Int32,
      failed_verifications : Int32

    def run_impl
      dataset_id = option("dataset")
      verbose = option("verbose") == "true"
      strict = option("strict") == "true"

      datasets = fetch_datasets(dataset_id)

      if datasets.empty?
        Log.info { "No datasets found to verify" }
        return
      end

      Log.info { "Verifying #{datasets.size} dataset(s)..." }
      Log.info { "" }

      summary = verify_all_datasets(datasets, verbose, strict)
      print_summary(summary)
    end

    # Fetch datasets from database
    protected def fetch_datasets(dataset_id : String?)
      if dataset_id && !dataset_id.empty?
        # Verify specific dataset
        result = root.database.query_all(
          "SELECT id, name, metadata FROM datasets WHERE id = ?",
          dataset_id
        ) do |dataset|
          {
            id:       dataset.read(String),
            name:     dataset.read(String),
            metadata: dataset.read(String),
          }
        end

        if result.empty?
          raise Command::UpdError.new("Dataset not found: #{dataset_id}", self)
        end

        result
      else
        # Verify all datasets
        root.database.query_all("SELECT id, name, metadata FROM datasets") do |dataset|
          {
            id:       dataset.read(String),
            name:     dataset.read(String),
            metadata: dataset.read(String),
          }
        end
      end
    end

    # Verify all datasets
    protected def verify_all_datasets(datasets, verbose : Bool, strict : Bool) : VerificationSummary
      total_datasets = 0
      total_signatures = 0
      failed_verifications = 0

      datasets.each do |dataset|
        total_datasets += 1
        dataset_id = dataset[:id]
        dataset_name = dataset[:name]
        metadata = dataset[:metadata]

        Log.info { "Dataset: #{dataset_name} (#{dataset_id})" }
        Log.info { "-" * 80 } if verbose

        failures = verify_dataset(dataset_id, dataset_name, metadata, verbose, strict)

        total_signatures += failures[:signature_count]
        failed_verifications += failures[:failures]

        Log.info { "" } unless verbose
      end

      VerificationSummary.new(
        total_datasets: total_datasets,
        total_signatures: total_signatures,
        failed_verifications: failed_verifications
      )
    end

    # Verify a single dataset
    protected def verify_dataset(
      dataset_id : String,
      dataset_name : String,
      metadata : String,
      verbose : Bool,
      strict : Bool,
    )
      result = {signature_count: 0, failures: 0}.to_h

      # Parse metadata
      metadata_json = UPD::SignatureValidator.parse_metadata(metadata)
      unless metadata_json
        Log.info { "  ✗ Invalid JSON metadata" }
        result[:failures] += 1
        return result
      end

      # Extract signatures
      content_signatures = UPD::SignatureValidator.extract_signatures(metadata_json)

      if content_signatures.empty?
        Log.info { "  - No signatures found" }
        return result
      end

      Log.info { "  Found #{content_signatures.size} signature(s)" } if verbose

      # Verify each signature
      content_signatures.each_with_index do |sig, idx|
        result[:signature_count] += 1
        sig_num = content_signatures.size > 1 ? " ##{idx + 1}" : ""

        success = verify_single_signature(
          dataset_id,
          sig,
          sig_num,
          verbose,
          strict
        )

        result[:failures] += 1 unless success
      end

      result
    end

    # Verify a single signature
    protected def verify_single_signature(
      dataset_id : String,
      sig : JSON::Any,
      sig_num : String,
      verbose : Bool,
      strict : Bool,
    ) : Bool
      # Extract signature data using validator
      sig_data = UPD::SignatureValidator.extract_signature_data(sig)

      if verbose
        print_signature_info(sig_data, sig_num)
      end

      # Use the validator to verify the signature
      verification_result = UPD::SignatureValidator.verify_signature(
        root.database,
        dataset_id,
        sig_data,
        strict
      )

      if verification_result.success
        Log.info { "  ✓ Signature#{sig_num} valid" }
        true
      else
        Log.info { "  ✗ Signature#{sig_num} INVALID: #{verification_result.message}" }
        false
      end
    rescue e
      Log.info { "  ✗ Signature#{sig_num} INVALID: #{e.message}" }
      false
    end

    # Print signature information (verbose mode)
    protected def print_signature_info(sig_data : UPD::SignatureValidator::SignatureData, sig_num : String)
      Log.info { "  Signature#{sig_num}:" }
      Log.info { "    Signed at: #{sig_data.signed_at}" }
      Log.info { "    Algorithm: #{sig_data.algorithm}" }
      Log.info { "    Curve: #{sig_data.curve}" }
      Log.info { "    Flavor tables: #{sig_data.signed_flavor_tables.join(", ")}" } if !sig_data.signed_flavor_tables.empty?
    end

    # Print verification summary
    protected def print_summary(summary : VerificationSummary)
      Log.info { "=" * 80 }
      Log.info { "Verification Summary:" }
      Log.info { "  Datasets verified: #{summary.total_datasets}" }
      Log.info { "  Total signatures: #{summary.total_signatures}" }
      Log.info { "  Failed verifications: #{summary.failed_verifications}" }

      if summary.failed_verifications > 0
        Log.info { "" }
        raise Command::UpdError.new("⚠️  Some signatures failed verification!", self)
      else
        Log.info { "" }
        Log.info { "✓ All signatures valid" }
      end
    end
  end
end
