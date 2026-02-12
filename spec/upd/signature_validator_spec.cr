require "spec"
require "../../src/upd/signature_validator"

describe UPD::SignatureValidator do
  describe ".validate_algorithm" do
    context "with supported algorithms" do
      it "accepts SHA256" do
        UPD::SignatureValidator.validate_algorithm("SHA256")
      end

      it "accepts SHA512" do
        UPD::SignatureValidator.validate_algorithm("SHA512")
      end
    end

    context "with unsupported algorithms" do
      it "rejects MD5" do
        expect_raises(Exception, /Unsupported hash algorithm: MD5/) do
          UPD::SignatureValidator.validate_algorithm("MD5")
        end
      end

      it "rejects SHA1" do
        expect_raises(Exception, /Unsupported hash algorithm: SHA1/) do
          UPD::SignatureValidator.validate_algorithm("SHA1")
        end
      end

      it "rejects empty string" do
        expect_raises(Exception) do
          UPD::SignatureValidator.validate_algorithm("")
        end
      end

      it "provides helpful error message" do
        begin
          UPD::SignatureValidator.validate_algorithm("INVALID")
          fail "Should have raised exception"
        rescue e : Exception
          message = e.message
          message.should_not  be_nil
          message.should contain("supported: SHA256, SHA512") if message
        end
      end
    end
  end

  describe ".validate_curve" do
    it "accepts secp256r1" do
      UPD::SignatureValidator.validate_curve("secp256r1")
    end

    it "rejects secp384r1" do
      expect_raises(Exception, /secp384r1/) do
        UPD::SignatureValidator.validate_curve("secp384r1")
      end
    end

    it "rejects ed25519" do
      expect_raises(Exception, /ed25519/) do
        UPD::SignatureValidator.validate_curve("ed25519")
      end
    end

    it "rejects empty string" do
      expect_raises(Exception) do
        UPD::SignatureValidator.validate_curve("")
      end
    end
  end

  describe ".parse_metadata" do
    context "with valid JSON" do
      it "parses simple object" do
        json = %{{"key": "value"}}
        result = UPD::SignatureValidator.parse_metadata(json)

        result.should_not be_nil
        result.not_nil!["key"].as_s.should eq("value")
      end

      it "parses complex nested object" do
        json = %{{"outer": {"inner": [1, 2, 3]}}}
        result = UPD::SignatureValidator.parse_metadata(json)

        result.should_not be_nil
        inner = result.not_nil!["outer"]["inner"].as_a
        inner.size.should eq(3)
      end

      it "parses empty object" do
        json = %{{}}
        result = UPD::SignatureValidator.parse_metadata(json)

        result.should_not be_nil
        result.not_nil!.should be_empty
      end
    end

    context "with invalid JSON" do
      it "returns nil for malformed JSON" do
        result = UPD::SignatureValidator.parse_metadata("not json")
        result.should be_nil
      end

      it "returns nil for incomplete JSON" do
        result = UPD::SignatureValidator.parse_metadata(%{{"key": }})
        result.should be_nil
      end

      it "returns nil for trailing comma" do
        result = UPD::SignatureValidator.parse_metadata(%{{"key": "value",}})
        result.should be_nil
      end
    end
  end

  describe ".extract_signatures" do
    it "extracts signature array" do
      metadata = JSON.parse(%{
        {
          "Content-Signature": [
            {"signature": "sig1"},
            {"signature": "sig2"}
          ]
        }
      }).as_h

      signatures = UPD::SignatureValidator.extract_signatures(metadata)

      signatures.size.should eq(2)
    end

    it "returns empty array when no signatures" do
      metadata = JSON.parse(%{{"other": "data"}}).as_h
      signatures = UPD::SignatureValidator.extract_signatures(metadata)

      signatures.should be_empty
    end

    it "handles null Content-Signature" do
      metadata = JSON.parse(%{{"Content-Signature": null}}).as_h
      signatures = UPD::SignatureValidator.extract_signatures(metadata)

      signatures.should be_empty
    end

    it "handles non-array Content-Signature" do
      metadata = JSON.parse(%{{"Content-Signature": "string"}}).as_h
      signatures = UPD::SignatureValidator.extract_signatures(metadata)

      signatures.should be_empty
    end
  end

  describe ".extract_signature_data" do
    it "extracts all required fields" do
      sig_json = JSON.parse(%{
        {
          "signature": "c2lnbmF0dXJl",
          "certificate": "Y2VydGlmaWNhdGU=",
          "dataHash": "abc123",
          "schemaHash": "def456",
          "dataHashAlgorithm": "SHA256",
          "curve": "secp256r1",
          "signedAt": "2024-01-01T00:00:00Z",
          "signedFlavorTables": ["flavor1", "flavor2"]
        }
      })

      sig_data = UPD::SignatureValidator.extract_signature_data(sig_json)

      sig_data.signature_b64.should eq("c2lnbmF0dXJl")
      sig_data.certificate_b64.should eq("Y2VydGlmaWNhdGU=")
      sig_data.expected_data_hash.should eq("abc123")
      sig_data.expected_schema_hash.should eq("def456")
      sig_data.algorithm.should eq("SHA256")
      sig_data.curve.should eq("secp256r1")
      sig_data.signed_at.should eq("2024-01-01T00:00:00Z")
      sig_data.signed_flavor_tables.should eq(["flavor1", "flavor2"])
    end

    it "handles missing signedFlavorTables" do
      sig_json = JSON.parse(%{
        {
          "signature": "c2lnbmF0dXJl",
          "certificate": "Y2VydGlmaWNhdGU=",
          "dataHash": "abc123",
          "schemaHash": "def456",
          "dataHashAlgorithm": "SHA256",
          "curve": "secp256r1",
          "signedAt": "2024-01-01T00:00:00Z"
        }
      })

      sig_data = UPD::SignatureValidator.extract_signature_data(sig_json)

      sig_data.signed_flavor_tables.should be_empty
    end

    it "raises on missing required field" do
      sig_json = JSON.parse(%{{"signature": "sig"}})

      expect_raises(Exception) do
        UPD::SignatureValidator.extract_signature_data(sig_json)
      end
    end
  end

  describe ".parse_certificate" do
    it "parses valid certificate" do
      # Generate a test certificate
      key = OpenSSL::PKey::EC.generate_by_curve_name("prime256v1")
      cert = OpenSSL::X509::Certificate.new
      cert.subject = OpenSSL::X509::Name.parse("CN=Test")
      cert.issuer = cert.subject
      cert.public_key = key
      cert.not_before = OpenSSL::ASN1::Time.days_from_now(-1)
      cert.not_after = OpenSSL::ASN1::Time.days_from_now(1)
      cert.serial = 1
      cert.version = 2
      cert.sign(key, OpenSSL::Digest.new("SHA256"))

      cert_pem = cert.to_pem
      cert_b64 = Base64.strict_encode(cert_pem)

      parsed = UPD::SignatureValidator.parse_certificate(cert_b64)

      parsed.should be_a(OpenSSL::X509::Certificate)

      parsed.subject.to_a.should contain({"CN", "Test"})
    end

    it "raises on invalid base64" do
      expect_raises(Exception) do
        UPD::SignatureValidator.parse_certificate("not-base64!!!")
      end
    end

    it "raises on invalid certificate data" do
      invalid_data = Base64.strict_encode("not a certificate")

      expect_raises(Exception) do
        UPD::SignatureValidator.parse_certificate(invalid_data)
      end
    end
  end

  describe ".extract_ec_key" do
    it "extracts EC key from EC certificate" do
      # Generate a test certificate with EC key
      key = OpenSSL::PKey::EC.generate_by_curve_name("prime256v1")
      cert = OpenSSL::X509::Certificate.new
      cert.subject = OpenSSL::X509::Name.parse("CN=Test")
      cert.issuer = cert.subject
      cert.public_key = key
      cert.not_before = OpenSSL::ASN1::Time.days_from_now(-1)
      cert.not_after = OpenSSL::ASN1::Time.days_from_now(1)
      cert.serial = 1
      cert.version = 2
      cert.sign(key, OpenSSL::Digest.new("SHA256"))

      ec_key = UPD::SignatureValidator.extract_ec_key(cert)

      ec_key.should be_a(OpenSSL::PKey::EC)
      String.new(LibCrypto.obj_nid2sn(LibCrypto.ec_group_get_curve_name(ec_key.group))).should eq("prime256v1")
    end

    it "raises error for non-EC key" do
      # Generate a test certificate with RSA key
      key = OpenSSL::PKey::RSA.generate(2048, 65537)
      cert = OpenSSL::X509::Certificate.new
      cert.subject = OpenSSL::X509::Name.parse("CN=Test")
      cert.issuer = cert.subject
      cert.public_key = key
      cert.not_before = OpenSSL::ASN1::Time.days_from_now(-1)
      cert.not_after = OpenSSL::ASN1::Time.days_from_now(1)
      cert.serial = 1
      cert.version = 2
      cert.sign(key, OpenSSL::Digest.new("SHA256"))

      expect_raises(Exception, /Public key is not an EC key/) do
        UPD::SignatureValidator.extract_ec_key(cert)
      end
    end
  end

  describe ".verify_certificate_validity" do
    context "with valid certificate" do
      it "accepts currently valid certificate" do
        key = OpenSSL::PKey::EC.generate_by_curve_name("prime256v1")
        cert = OpenSSL::X509::Certificate.new
        cert.subject = OpenSSL::X509::Name.parse("CN=Test")
        cert.issuer = cert.subject
        cert.public_key = key
        cert.not_before = OpenSSL::ASN1::Time.days_from_now(-1)
        cert.not_after = OpenSSL::ASN1::Time.days_from_now(1)
        cert.serial = 1
        cert.version = 2
        cert.sign(key, OpenSSL::Digest.new("SHA256"))

        UPD::SignatureValidator.verify_certificate_validity(cert)
      end
    end

    context "with expired certificate" do
      it "rejects expired certificate" do
        key = OpenSSL::PKey::EC.generate_by_curve_name("prime256v1")
        cert = OpenSSL::X509::Certificate.new
        cert.subject = OpenSSL::X509::Name.parse("CN=Test")
        cert.issuer = cert.subject
        cert.public_key = key
        cert.not_before = OpenSSL::ASN1::Time.days_from_now(-2)
        cert.not_after = OpenSSL::ASN1::Time.days_from_now(-1)
        cert.serial = 1
        cert.version = 2
        cert.sign(key, OpenSSL::Digest.new("SHA256"))

        expect_raises(Exception, /expired/) do
          UPD::SignatureValidator.verify_certificate_validity(cert)
        end
      end

      it "includes expiry date in error" do
        key = OpenSSL::PKey::EC.generate_by_curve_name("prime256v1")
        cert = OpenSSL::X509::Certificate.new
        cert.subject = OpenSSL::X509::Name.parse("CN=Test")
        cert.issuer = cert.subject
        cert.public_key = key
        cert.not_before = OpenSSL::ASN1::Time.days_from_now(-2)
        cert.not_after = OpenSSL::ASN1::Time.days_from_now(-1)
        cert.serial = 1
        cert.version = 2
        cert.sign(key, OpenSSL::Digest.new("SHA256"))

        begin
          UPD::SignatureValidator.verify_certificate_validity(cert)
          fail "Should raise"
        rescue e : Exception
          message = e.message
          message.should_not be nil
          message.should contain("not_after") if message
        end
      end
    end

    context "with not-yet-valid certificate" do
      it "rejects future certificate" do
        key = OpenSSL::PKey::EC.generate_by_curve_name("prime256v1")
        cert = OpenSSL::X509::Certificate.new
        cert.subject = OpenSSL::X509::Name.parse("CN=Test")
        cert.issuer = cert.subject
        cert.public_key = key
        cert.not_before = OpenSSL::ASN1::Time.days_from_now(+1)
        cert.not_after = OpenSSL::ASN1::Time.days_from_now(+2)
        cert.serial = 1
        cert.version = 2
        cert.sign(key, OpenSSL::Digest.new("SHA256"))

        expect_raises(Exception, /not yet valid/) do
          UPD::SignatureValidator.verify_certificate_validity(cert)
        end
      end
    end
  end

  describe ".verify_ecdsa_signature" do
    it "verifies valid signature" do
      # Generate test key and sign data
      key = OpenSSL::PKey::EC.generate_by_curve_name("prime256v1")
      data_hash = "abc123def4567890"
      signature = key.ec_sign(data_hash.hexbytes)

      # Verify with public key
      UPD::SignatureValidator.verify_ecdsa_signature(key, data_hash, signature)
    end

    it "rejects invalid signature" do
      key = OpenSSL::PKey::EC.generate_by_curve_name("prime256v1")
      data_hash = "abc123def4567890"
      invalid_signature = Random::Secure.random_bytes(64)

      expect_raises(OpenSSL::PKey::EcError) do
        UPD::SignatureValidator.verify_ecdsa_signature(key, data_hash, invalid_signature)
      end
    end

    it "rejects signature for wrong data" do
      key = OpenSSL::PKey::EC.generate_by_curve_name("prime256v1")
      original_hash = "abc123"
      different_hash = "def789"
      signature = key.ec_sign(original_hash.hexbytes)

      expect_raises(Exception, /verification failed/) do
        UPD::SignatureValidator.verify_ecdsa_signature(key, different_hash, signature)
      end
    end
  end

  describe "VerificationResult" do
    it "creates a successful result" do
      result = UPD::SignatureValidator::VerificationResult.new(
        success: true,
        message: "Test message",
        signature_number: 1
      )

      result.success.should eq(true)
      result.message.should eq("Test message")
      result.signature_number.should eq(1)
    end

    it "creates a failed result" do
      result = UPD::SignatureValidator::VerificationResult.new(
        success: false,
        message: "Error message"
      )

      result.success.should eq(false)
      result.message.should eq("Error message")
      result.signature_number.should be_nil
    end
  end

  describe "SignatureData" do
    it "creates signature data with all fields" do
      sig_data = UPD::SignatureValidator::SignatureData.new(
        signature_b64: "base64sig",
        certificate_b64: "base64cert",
        expected_data_hash: "datahash123",
        expected_schema_hash: "schemahash456",
        algorithm: "SHA256",
        curve: "secp256r1",
        signed_at: "2024-01-01T00:00:00Z",
        signed_flavor_tables: ["table1", "table2"]
      )

      sig_data.algorithm.should eq("SHA256")
      sig_data.curve.should eq("secp256r1")
      sig_data.signed_flavor_tables.should eq(["table1", "table2"])
    end
  end
end
