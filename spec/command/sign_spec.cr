require "spec"
require "json"
require "base64"
require "openssl"
require "openssl_ext"
require "duckdb"
# require "tempfile"
require "../../src/command/**"
require "file_utils"
# Helper methods
module SignSpecHelpers
  def self.create_test_key_and_cert
    # Generate EC key
    # key = OpenSSL::PKey::EC.generate_by_curve_name("secp256r1")
    key = OpenSSL::PKey::EC.generate_by_curve_name("prime256v1")

    # Create self-signed certificate
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    name = OpenSSL::X509::Name.new
    name.add_entry("C", "US")
    name.add_entry("O", "Test")
    name.add_entry("CN", "Test")

    cert.subject = name
    cert.issuer = name
    # cert.subject = OpenSSL::X509::Name.parse("C=US,O=Test,CN=Test")
    # cert.issuer = cert.subject
    cert.public_key = key
    cert.not_before = OpenSSL::ASN1::Time.days_from_now(0)
    cert.not_after = OpenSSL::ASN1::Time.days_from_now(365)
    cert.sign(key, OpenSSL::Digest.new("SHA256"))

    {key, cert}
  end
end

describe Command::Signature do
  describe "JSON serialization" do
    it "creates signature record with all required fields" do
      sig = Command::Signature.new(
        signature: "base64_signature",
        dataHashAlgorithm: "SHA256",
        dataHash: "abcd1234",
        schemaHash: "efgh5678",
        certificate: "base64_cert",
        curve: "secp256r1",
        signedAt: "2025-01-01T00:00:00Z",
        signedFlavorTables: ["custom_table"]
      )

      sig.signature.should eq("base64_signature")
      sig.dataHashAlgorithm.should eq("SHA256")
      sig.dataHash.should eq("abcd1234")
      sig.schemaHash.should eq("efgh5678")
      sig.certificate.should eq("base64_cert")
      sig.curve.should eq("secp256r1")
      sig.signedAt.should eq("2025-01-01T00:00:00Z")
      sig.signedFlavorTables.should eq(["custom_table"])
    end

    it "converts to JSON correctly" do
      sig = Command::Signature.new(
        signature: "sig",
        dataHashAlgorithm: "SHA256",
        dataHash: "hash",
        schemaHash: "schema",
        certificate: "cert",
        curve: "secp256r1",
        signedAt: "2025-01-01T00:00:00Z",
        signedFlavorTables: [] of String
      )

      json = sig.to_json
      parsed = JSON.parse(json)

      parsed["signature"].as_s.should eq("sig")
      parsed["dataHashAlgorithm"].as_s.should eq("SHA256")
      parsed["dataHash"].as_s.should eq("hash")
      parsed["schemaHash"].as_s.should eq("schema")
      parsed["certificate"].as_s.should eq("cert")
      parsed["curve"].as_s.should eq("secp256r1")
      parsed["signedAt"].as_s.should eq("2025-01-01T00:00:00Z")
      parsed["signedFlavorTables"].as_a.should be_empty
    end

    it "converts to hash correctly" do
      sig = Command::Signature.new(
        signature: "sig",
        dataHashAlgorithm: "SHA256",
        dataHash: "hash",
        schemaHash: "schema",
        certificate: "cert",
        curve: "secp256r1",
        signedAt: "2025-01-01T00:00:00Z",
        signedFlavorTables: ["table1", "table2"]
      )

      hash = sig.to_h

      hash["signature"].should eq("sig")
      hash["dataHashAlgorithm"].should eq("SHA256")
      hash["dataHash"].should eq("hash")
      hash["schemaHash"].should eq("schema")
      hash["certificate"].should eq("cert")
      hash["curve"].should eq("secp256r1")
      hash["signedAt"].should eq("2025-01-01T00:00:00Z")
      hash["signedFlavorTables"].should eq(["table1", "table2"])
    end
  end
end

describe Command::Sign do
  # ...
  Spec.before_each do
    Command::Root.new([
      Command::Argument.new("input", :optlong, "test.upd"),
      Command::Argument.new("init", :pos, nil),
    ]).run
  end
  Spec.after_each do
    FileUtils.rm_rf("test.upd")
  end
  # ...

  describe "algorithm validation" do
    it "accepts SHA256 algorithm" do
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test', 'image', '{}')")
        db.close
      end

      key, cert = SignSpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          root = Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("sign", :pos, nil),
            Command::Argument.new("key", :optlong, key_file.path),
            Command::Argument.new("cert", :optlong, cert_file.path),
            Command::Argument.new("algorithm", :optlong, "SHA256"),
            Command::Argument.new("dataset", :optlong, "ds-1")
          ]).run
        end
      end
    end

    it "accepts SHA512 algorithm" do
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test', 'image', '{}')")
        db.close
      end

      key, cert = SignSpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          root = Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("sign", :pos, nil),
            Command::Argument.new("key", :optlong, key_file.path),
            Command::Argument.new("cert", :optlong, cert_file.path),
            Command::Argument.new("algorithm", :optlong, "SHA512"),
            Command::Argument.new("dataset", :optlong, "ds-1")
          ])
          root.run
        end
      end
    end

    it "rejects unsupported hash algorithms" do
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test', 'image', '{}')")
        db.close
      end

      key, cert = SignSpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          expect_raises(Command::UpdError, /Unsupported hash algorithm: MD5/) do
            Command::Root.new([
              Command::Argument.new("input", :optlong, "test.upd"),
              Command::Argument.new("sign", :pos, nil),
              Command::Argument.new("key", :optlong, key_file.path),
              Command::Argument.new("cert", :optlong, cert_file.path),
              Command::Argument.new("algorithm", :optlong, "MD5"),
              Command::Argument.new("dataset", :optlong, "ds-1")
            ]).run
          end
        end
      end
    end
  end

  describe "curve validation" do
    it "accepts secp256r1 curve" do
      # secp256r1 (also known as prime256v1 or P-256) is the recommended curve
      # This is tested in the integration tests above
    end

    it "rejects unsupported curves" do
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test', 'image', '{}')")
        db.close
      end

      key, cert = SignSpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          expect_raises(Command::UpdError, /Unsupported ECDSA curve: secp384r1/) do
            Command::Root.new([
              Command::Argument.new("input", :optlong, "test.upd"),
              Command::Argument.new("sign", :pos, nil),
              Command::Argument.new("key", :optlong, key_file.path),
              Command::Argument.new("cert", :optlong, cert_file.path),
              Command::Argument.new("curve", :optlong, "secp384r1"),
              Command::Argument.new("dataset", :optlong, "ds-1")
            ]).run
          end
        end
      end
    end
  end

  describe "flavor tables support" do
    it "includes flavor tables in signature" do
      DB.connect("duckdb://test.upd") do |db|
        db.exec("CREATE TABLE custom_table (id VARCHAR PRIMARY KEY, dataset_id VARCHAR, data VARCHAR)")
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test', 'image', '{}')")
        db.close
      end

      key, cert = SignSpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          root = Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("sign", :pos, nil),
            Command::Argument.new("key", :optlong, key_file.path),
            Command::Argument.new("cert", :optlong, cert_file.path),
            Command::Argument.new("flavor-tables", :optlong, "custom_table"),
            Command::Argument.new("dataset", :optlong, "ds-1")
          ])
          root.run

          metadata : String
          # Verify signature was created with flavor tables
          DB.open("duckdb://test.upd") do |db|
            metadata = db.query_one("SELECT metadata FROM datasets WHERE id = 'ds-1'") { |r| r.read(String) }
            db.close

            metadata_json = JSON.parse(metadata)
            signatures = metadata_json["Content-Signature"].as_a
            signatures.size.should eq(1)

            flavor_tables = signatures[0]["signedFlavorTables"].as_a
            flavor_tables.size.should eq(1)
            flavor_tables[0].as_s.should eq("custom_table")
          end
        end
      end
    end

    it "handles multiple flavor tables" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("CREATE TABLE table1 (id VARCHAR PRIMARY KEY, dataset_id VARCHAR)")
        db.exec("CREATE TABLE table2 (id VARCHAR PRIMARY KEY, dataset_id VARCHAR)")
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test', 'image', '{}')")
        db.close
      end

      key, cert = SignSpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          root = Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("sign", :pos, nil),
            Command::Argument.new("key", :optlong, key_file.path),
            Command::Argument.new("cert", :optlong, cert_file.path),
            Command::Argument.new("flavor-tables", :optlong, "table1,table2"),
            Command::Argument.new("dataset", :optlong, "ds-1")
          ])
          root.run

          DB.open("duckdb://test.upd") do |db|
            metadata = db.query_one("SELECT metadata FROM datasets WHERE id = 'ds-1'") { |r| r.read(String) }
            db.close

            metadata_json = JSON.parse(metadata)
            signatures = metadata_json["Content-Signature"].as_a
            flavor_tables = signatures[0]["signedFlavorTables"].as_a.map(&.as_s)

            flavor_tables.should eq(["table1", "table2"])
          end
        end
      end
    end
  end

  describe "multiple signatures" do
    it "appends new signature to existing ones" do
      DB.open("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test', 'image', '{}')")
        db.close
      end

      key1, cert1 = SignSpecHelpers.create_test_key_and_cert
      key2, cert2 = SignSpecHelpers.create_test_key_and_cert

      File.tempfile("key1") do |key1_file|
        File.tempfile("cert1") do |cert1_file|
          File.write(key1_file.path, key1.to_pem)
          File.write(cert1_file.path, cert1.to_pem)

          # Sign with first key
          root = Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("sign", :pos, nil),
            Command::Argument.new("key", :optlong, key1_file.path),
            Command::Argument.new("cert", :optlong, cert1_file.path),
            Command::Argument.new("dataset", :optlong, "ds-1")
          ])
          root.run

          File.tempfile("key2") do |key2_file|
            File.tempfile("cert2") do |cert2_file|
              File.write(key2_file.path, key2.to_pem)
              File.write(cert2_file.path, cert2.to_pem)

              # Sign with second key
              root2 = Command::Root.new([
                Command::Argument.new("input", :optlong, "test.upd"),
                Command::Argument.new("sign", :pos, nil),
                Command::Argument.new("key", :optlong, key2_file.path),
                Command::Argument.new("cert", :optlong, cert2_file.path),
                Command::Argument.new("dataset", :optlong, "ds-1")
              ])


              root2.run
              # Verify two signatures exist
              DB.open("duckdb://test.upd") do |db|
                metadata = db.query_one("SELECT metadata FROM datasets WHERE id = 'ds-1'") { |r| r.read(String) }
                db.close
                metadata_json = JSON.parse(metadata)
                signatures = metadata_json["Content-Signature"].as_a
                signatures.size.should eq(2)
              end
            end
          end
        end
      end
    end
  end

  describe "error handling" do
    it "reports error when dataset not found" do
      key, cert = SignSpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          expect_raises(Command::UpdError, /Dataset not found: nonexistent-id/) do
            Command::Root.new([
              Command::Argument.new("input", :optlong, "test.upd"),
              Command::Argument.new("sign", :pos, nil),
              Command::Argument.new("key", :optlong, key_file.path),
              Command::Argument.new("cert", :optlong, cert_file.path),
              Command::Argument.new("dataset", :optlong, "nonexistent-id")
            ]).run
          end
        end
      end
    end

    it "reports error when key file not found" do
      expect_raises(Command::UpdError, /Private key file not found/) do
        Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("sign", :pos, nil),
          Command::Argument.new("key", :optlong, "/nonexistent/key.pem"),
          Command::Argument.new("cert", :optlong, "/nonexistent/cert.pem"),
          Command::Argument.new("dataset", :optlong, "ds-1")
        ]).run
      end
    end

    it "reports error when certificate file not found" do
      key, _ = SignSpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.write(key_file.path, key.to_pem)

        expect_raises(Command::UpdError, /Certificate file not found/) do
          Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("sign", :pos, nil),
            Command::Argument.new("key", :optlong, key_file.path),
            Command::Argument.new("cert", :optlong, "/nonexistent/cert.pem"),
            Command::Argument.new("dataset", :optlong, "ds-1")
          ]).run
        end
      end
    end
  end
end
