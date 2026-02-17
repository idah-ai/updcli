require "digest/sha256"
require "digest/sha512"
require "base64"
require "openssl_ext"
require "json"

module UPD
  # SignatureValidator - Core signature verification logic
  # This class is completely independent of CLI infrastructure for easy testing
  class SignatureValidator
    # Result of a single signature verification
    record VerificationResult,
      success : Bool,
      message : String,
      signature_number : Int32? = nil

    # Structured signature data
    record SignatureData,
      signature_b64 : String,
      certificate_b64 : String,
      expected_data_hash : String,
      expected_schema_hash : String,
      algorithm : String,
      curve : String,
      signed_at : String,
      signed_flavor_tables : Array(String)

    # Validation Methods - Pure functions, easy to test

    def self.validate_algorithm(algorithm : String)
      unless ["SHA256", "SHA512"].includes?(algorithm)
        raise "Unsupported hash algorithm: #{algorithm} (supported: SHA256, SHA512)"
      end || true
    end

    def self.validate_curve(curve : String)
      unless ["secp256r1"].includes?(curve)
        raise "Unsupported ECDSA curve: #{curve} (supported: secp256r1)"
      end
    end

    # Parse metadata JSON
    def self.parse_metadata(metadata : String) : Hash(String, JSON::Any)?
      JSON.parse(metadata).as_h
    rescue
      nil
    end

    # Extract signatures from metadata
    def self.extract_signatures(metadata_json : Hash(String, JSON::Any)) : Array(JSON::Any)
      if sig = metadata_json["Content-Signature"]?
        sig.as_a
      else
        [] of JSON::Any
      end
    rescue
      [] of JSON::Any
    end

    # Extract signature data from JSON
    def self.extract_signature_data(sig : JSON::Any) : SignatureData
      signed_flavor_tables = begin
        sig["signedFlavorTables"].as_a.map(&.as_s)
      rescue
        [] of String
      end

      SignatureData.new(
        signature_b64: sig["signature"].as_s,
        certificate_b64: sig["certificate"].as_s,
        expected_data_hash: sig["dataHash"].as_s,
        expected_schema_hash: sig["schemaHash"].as_s,
        algorithm: sig["dataHashAlgorithm"].as_s,
        curve: sig["curve"].as_s,
        signed_at: sig["signedAt"].as_s,
        signed_flavor_tables: signed_flavor_tables
      )
    end

    # Certificate Operations

    def self.parse_certificate(certificate_b64 : String) : OpenSSL::X509::Certificate
      OpenSSL::X509::Certificate.new(String.new(Base64.decode(certificate_b64)))
    end

    def self.extract_ec_key(certificate : OpenSSL::X509::Certificate) : OpenSSL::PKey::EC
      public_key = certificate.public_key

      unless public_key.is_a?(OpenSSL::PKey::EC)
        raise "Public key is not an EC key"
      end

      public_key.as(OpenSSL::PKey::EC)
    end

    def self.verify_certificate_validity(certificate : OpenSSL::X509::Certificate)
      now = Time.utc

      if certificate.not_before > now
        raise "Certificate not yet valid (not_before: #{certificate.not_before})"
      end

      if certificate.not_after < now
        raise "Certificate expired (not_after: #{certificate.not_after})"
      end
    end

    # Hash Verification

    def self.verify_data_hash(
      database : DB::Connection,
      dataset_id : String,
      tables_to_serialize : Array(String),
      algorithm : String,
      expected_hash : String,
    ) : String
      computed_hash = UPD::Serialization.compute_data_hash(
        database,
        dataset_id,
        tables_to_serialize,
        algorithm
      )

      unless computed_hash == expected_hash
        raise "Data hash mismatch!\n" +
              "    Expected: #{expected_hash}\n" +
              "    Computed: #{computed_hash}"
      end

      computed_hash
    end

    def self.verify_schema_hash(
      database : DB::Connection,
      tables_to_serialize : Array(String),
      algorithm : String,
      expected_hash : String,
    ) : String
      computed_hash = UPD::Serialization.compute_schema_hash(
        database,
        tables_to_serialize,
        algorithm
      )

      unless computed_hash == expected_hash
        raise "Schema hash mismatch!\n" +
              "    Expected: #{expected_hash}\n" +
              "    Computed: #{computed_hash}"
      end

      computed_hash
    end

    # Signature Verification

    def self.verify_ecdsa_signature(
      ec_key : OpenSSL::PKey::EC,
      data_hash : String,
      signature : Bytes,
    )
      unless ec_key.ec_verify(data_hash.hexbytes, signature)
        raise "ECDSA signature verification failed"
      end
    end

    # Main verification method - coordinates all verification steps
    def self.verify_signature(
      database : DB::Connection,
      dataset_id : String,
      sig_data : SignatureData,
      strict : Bool = false,
    ) : VerificationResult
      # Validate algorithm and curve
      validate_algorithm(sig_data.algorithm)
      validate_curve(sig_data.curve)

      # Parse certificate and extract key
      signature = Base64.decode(sig_data.signature_b64)
      certificate = parse_certificate(sig_data.certificate_b64)
      ec_key = extract_ec_key(certificate)

      # Verify hashes
      tables_to_serialize = UPD::Serialization::CORE_TABLES_ORDER + sig_data.signed_flavor_tables

      verify_data_hash(
        database,
        dataset_id,
        tables_to_serialize,
        sig_data.algorithm,
        sig_data.expected_data_hash
      )

      verify_schema_hash(
        database,
        tables_to_serialize,
        sig_data.algorithm,
        sig_data.expected_schema_hash
      )

      # Verify ECDSA signature
      verify_ecdsa_signature(ec_key, sig_data.expected_data_hash, signature)

      # Optional: verify certificate validity
      if strict
        verify_certificate_validity(certificate)
      end

      VerificationResult.new(
        success: true,
        message: "Signature valid"
      )
    rescue e
      VerificationResult.new(
        success: false,
        message: e.message || "Unknown error"
      )
    end
  end
end
