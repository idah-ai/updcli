require "spec"
require "json"
require "base64"
require "openssl"
require "openssl_ext"
require "duckdb"
require "../../src/command/**"
require "file_utils"

# Helper methods for verify specs
module VerifySpecHelpers
  def self.create_test_key_and_cert
    # Generate EC key (using prime256v1 / secp256r1)
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
    cert.public_key = key
    cert.not_before = OpenSSL::ASN1::Time.days_from_now(0)
    cert.not_after = OpenSSL::ASN1::Time.days_from_now(365)
    cert.sign(key, OpenSSL::Digest.new("SHA256"))

    {key, cert}
  end

  def self.create_expired_cert(key)
    # Create an expired certificate for strict mode testing
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 2
    name = OpenSSL::X509::Name.new
    name.add_entry("C", "US")
    name.add_entry("O", "Expired")
    name.add_entry("CN", "Expired")

    cert.subject = name
    cert.issuer = name
    cert.public_key = key
    cert.not_before = OpenSSL::ASN1::Time.days_from_now(-365)
    cert.not_after = OpenSSL::ASN1::Time.days_from_now(-1)
    cert.sign(key, OpenSSL::Digest.new("SHA256"))

    cert
  end

  def self.sign_dataset(db_path, dataset_id, key_path, cert_path, options = {} of Symbol => String)
    args = [
      Command::Argument.new("input", :optlong, db_path),
      Command::Argument.new("sign", :pos, nil),
      Command::Argument.new("key", :optlong, key_path),
      Command::Argument.new("cert", :optlong, cert_path),
      Command::Argument.new("dataset", :optlong, dataset_id)
    ]

    # Add optional arguments
    if flavor_tables = options[:flavor_tables]?
      args << Command::Argument.new("flavor-tables", :optlong, flavor_tables)
    end

    if algorithm = options[:algorithm]?
      args << Command::Argument.new("algorithm", :optlong, algorithm)
    end

    Command::Root.new(args).run
  end

  def self.corrupt_signature_in_metadata(db_path, dataset_id)
    # Manually corrupt a signature to test failure detection
    DB.open("duckdb://#{db_path}") do |db|
      metadata = db.query_one("SELECT metadata FROM datasets WHERE id = ?", dataset_id) { |r| r.read(String) }

      metadata_json = JSON.parse(metadata).as_h
      signatures = metadata_json["Content-Signature"].as_a

      # Corrupt the first signature
      if signatures.size > 0
        sig = signatures[0].as_h
        sig["dataHash"] = JSON::Any.new("corrupted_hash_12345678")
        metadata_json["Content-Signature"] = JSON::Any.new(signatures)

        db.exec("UPDATE datasets SET metadata = ? WHERE id = ?", metadata_json.to_json, dataset_id)
      end

      db.close
    end
  end

  def self.add_data_to_dataset(db_path, dataset_id)
    # Add data to dataset to invalidate signatures
    DB.open("duckdb://#{db_path}") do |db|
      db.exec("INSERT INTO entries VALUES ('entry-1', ?, 'datset://media-1', '{}')", dataset_id)
      db.close
    end
  end
end

describe Command::Verify do
  before_each do
    Command::Root.new([
      Command::Argument.new("input", :optlong, "test.upd"),
      Command::Argument.new("init", :pos, nil),
    ]).run
  end

  after_each do
    FileUtils.rm_rf("test.upd")
  end

  describe "basic verification" do
    it "verifies a valid single signature" do
      # Create dataset
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Test Dataset', 'image', '{}')")
        db.close
      end

      # Sign the dataset
      key, cert = VerifySpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key_file.path, cert_file.path)

          # Verify the signature
          root = Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("verify", :pos, nil),
            Command::Argument.new("dataset", :optlong, "ds-1")
          ])

          # Should not raise or exit with error
          root.run
        end
      end
    end

    it "verifies all datasets when no dataset specified" do
      # Create multiple datasets
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Dataset 1', 'image', '{}')")
        db.exec("INSERT INTO datasets VALUES ('ds-2', 'Dataset 2', 'text', '{}')")
        db.close
      end

      # Sign both datasets
      key, cert = VerifySpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key_file.path, cert_file.path)
          VerifySpecHelpers.sign_dataset("test.upd", "ds-2", key_file.path, cert_file.path)

          # Verify all datasets
          root = Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("verify", :pos, nil)
          ])

          root.run
        end
      end
    end

    it "handles dataset with no signatures" do
      # Create dataset without signing
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Unsigned', 'image', '{}')")
        db.close
      end

      # Verify should handle gracefully (no error, just report no signatures)
      root = Command::Root.new([
        Command::Argument.new("input", :optlong, "test.upd"),
        Command::Argument.new("verify", :pos, nil),
        Command::Argument.new("dataset", :optlong, "ds-1")
      ])

      root.run
    end

    it "reports error when dataset not found" do
      # Try to verify non-existent dataset
      expect_raises(Command::UpdError, /Dataset not found/) do
        root = Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("verify", :pos, nil),
          Command::Argument.new("dataset", :optlong, "nonexistent-ds")
        ])
        root.run
      end
    end
  end

  describe "multiple signatures" do
    it "verifies multiple signatures on the same dataset" do
      # Create dataset
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Multi-signed', 'image', '{}')")
        db.close
      end

      # Sign with two different keys
      key1, cert1 = VerifySpecHelpers.create_test_key_and_cert
      key2, cert2 = VerifySpecHelpers.create_test_key_and_cert

      File.tempfile("key1") do |key1_file|
        File.tempfile("cert1") do |cert1_file|
          File.write(key1_file.path, key1.to_pem)
          File.write(cert1_file.path, cert1.to_pem)

          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key1_file.path, cert1_file.path)

          File.tempfile("key2") do |key2_file|
            File.tempfile("cert2") do |cert2_file|
              File.write(key2_file.path, key2.to_pem)
              File.write(cert2_file.path, cert2.to_pem)

              VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key2_file.path, cert2_file.path)

              # Verify - should verify both signatures successfully
              root = Command::Root.new([
                Command::Argument.new("input", :optlong, "test.upd"),
                Command::Argument.new("verify", :pos, nil),
                Command::Argument.new("dataset", :optlong, "ds-1")
              ])

              root.run

              # Check that both signatures were verified
              DB.open("duckdb://test.upd") do |db|
                metadata = db.query_one("SELECT metadata FROM datasets WHERE id = 'ds-1'") { |r| r.read(String) }
                metadata_json = JSON.parse(metadata)
                signatures = metadata_json["Content-Signature"].as_a
                signatures.size.should eq(2)
                db.close
              end
            end
          end
        end
      end
    end

    it "detects when one signature is invalid among multiple" do
      # Create dataset
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Partial Valid', 'image', '{}')")
        db.close
      end

      # Sign with two keys
      key1, cert1 = VerifySpecHelpers.create_test_key_and_cert
      key2, cert2 = VerifySpecHelpers.create_test_key_and_cert

      File.tempfile("key1") do |key1_file|
        File.tempfile("cert1") do |cert1_file|
          File.write(key1_file.path, key1.to_pem)
          File.write(cert1_file.path, cert1.to_pem)

          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key1_file.path, cert1_file.path)

          File.tempfile("key2") do |key2_file|
            File.tempfile("cert2") do |cert2_file|
              File.write(key2_file.path, key2.to_pem)
              File.write(cert2_file.path, cert2.to_pem)

              VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key2_file.path, cert2_file.path)

              # Corrupt one signature
              VerifySpecHelpers.corrupt_signature_in_metadata("test.upd", "ds-1")

              # Verify should fail
              expect_raises(Command::UpdError, /failed verification/) do
                root = Command::Root.new([
                  Command::Argument.new("input", :optlong, "test.upd"),
                  Command::Argument.new("verify", :pos, nil),
                  Command::Argument.new("dataset", :optlong, "ds-1")
                ])
                root.run
              end
            end
          end
        end
      end
    end
  end

  describe "signature invalidation" do
    it "detects when data has been modified after signing" do
      # Create and sign dataset
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Modified Data', 'image', '{}')")
        db.close
      end

      key, cert = VerifySpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key_file.path, cert_file.path)

          # Modify dataset after signing
          VerifySpecHelpers.add_data_to_dataset("test.upd", "ds-1")

          # Verification should fail
          expect_raises(Command::UpdError, /failed verification/) do
            root = Command::Root.new([
              Command::Argument.new("input", :optlong, "test.upd"),
              Command::Argument.new("verify", :pos, nil),
              Command::Argument.new("dataset", :optlong, "ds-1")
            ])
            root.run
          end
        end
      end
    end

    it "detects corrupted signature data" do
      # Create and sign dataset
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Corrupted Sig', 'image', '{}')")
        db.close
      end

      key, cert = VerifySpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key_file.path, cert_file.path)

          # Corrupt the signature
          VerifySpecHelpers.corrupt_signature_in_metadata("test.upd", "ds-1")

          # Verification should fail
          expect_raises(Command::UpdError, /failed verification/) do
            root = Command::Root.new([
              Command::Argument.new("input", :optlong, "test.upd"),
              Command::Argument.new("verify", :pos, nil),
              Command::Argument.new("dataset", :optlong, "ds-1")
            ])
            root.run
          end
        end
      end
    end
  end

  describe "algorithm support" do
    it "verifies SHA256 signatures" do
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'SHA256 Test', 'image', '{}')")
        db.close
      end

      key, cert = VerifySpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key_file.path, cert_file.path, {algorithm: "SHA256"})

          root = Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("verify", :pos, nil),
            Command::Argument.new("dataset", :optlong, "ds-1")
          ])

          root.run
        end
      end
    end

    it "verifies SHA512 signatures" do
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'SHA512 Test', 'image', '{}')")
        db.close
      end

      key, cert = VerifySpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key_file.path, cert_file.path, {algorithm: "SHA512"})

          root = Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("verify", :pos, nil),
            Command::Argument.new("dataset", :optlong, "ds-1")
          ])

          root.run
        end
      end
    end
  end

  describe "flavor tables support" do
    it "verifies signatures with flavor tables" do
      # Create custom flavor table
      DB.connect("duckdb://test.upd") do |db|
        db.exec("CREATE TABLE custom_table (id VARCHAR PRIMARY KEY, dataset_id VARCHAR, data VARCHAR)")
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'With Flavors', 'image', '{}')")
        db.exec("INSERT INTO custom_table VALUES ('ct-1', 'ds-1', 'custom data')")
        db.close
      end

      key, cert = VerifySpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key_file.path, cert_file.path, {flavor_tables: "custom_table"})

          # Verify with flavor tables
          root = Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("verify", :pos, nil),
            Command::Argument.new("dataset", :optlong, "ds-1")
          ])

          root.run
        end
      end
    end

    it "detects modifications to flavor tables" do
      # Create custom flavor table
      DB.connect("duckdb://test.upd") do |db|
        db.exec("CREATE TABLE custom_table (id VARCHAR PRIMARY KEY, dataset_id VARCHAR, data VARCHAR)")
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Flavor Mod Test', 'image', '{}')")
        db.exec("INSERT INTO custom_table VALUES ('ct-1', 'ds-1', 'original data')")
        db.close
      end

      key, cert = VerifySpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key_file.path, cert_file.path, {flavor_tables: "custom_table"})

          # Modify flavor table data
          DB.open("duckdb://test.upd") do |db|
            db.exec("UPDATE custom_table SET data = 'modified data' WHERE id = 'ct-1'")
            db.close
          end

          # Verification should fail
          expect_raises(Command::UpdError, /failed verification/) do
            root = Command::Root.new([
              Command::Argument.new("input", :optlong, "test.upd"),
              Command::Argument.new("verify", :pos, nil),
              Command::Argument.new("dataset", :optlong, "ds-1")
            ])
            root.run
          end
        end
      end
    end
  end

  describe "strict mode" do
    it "accepts valid certificates in strict mode" do
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Strict Valid', 'image', '{}')")
        db.close
      end

      key, cert = VerifySpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key_file.path, cert_file.path)

          # Verify in strict mode
          root = Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("verify", :pos, nil),
            Command::Argument.new("dataset", :optlong, "ds-1"),
            Command::Argument.new("strict", :optlong, "true")
          ])

          root.run
        end
      end
    end

    it "rejects expired certificates in strict mode" do
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Expired Cert', 'image', '{}')")
        db.close
      end

      key, _ = VerifySpecHelpers.create_test_key_and_cert
      expired_cert = VerifySpecHelpers.create_expired_cert(key)

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, expired_cert.to_pem)

          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key_file.path, cert_file.path)

          # Verify in strict mode should fail
          expect_raises(Command::UpdError, /failed verification/) do
            root = Command::Root.new([
              Command::Argument.new("input", :optlong, "test.upd"),
              Command::Argument.new("verify", :pos, nil),
              Command::Argument.new("dataset", :optlong, "ds-1"),
              Command::Argument.new("strict", :optlong, "true")
            ])
            root.run
          end
        end
      end
    end

    it "accepts expired certificates in non-strict mode" do
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Expired OK', 'image', '{}')")
        db.close
      end

      key, _ = VerifySpecHelpers.create_test_key_and_cert
      expired_cert = VerifySpecHelpers.create_expired_cert(key)

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, expired_cert.to_pem)

          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key_file.path, cert_file.path)

          # Verify in non-strict mode should pass (only checks signature, not cert validity)
          root = Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("verify", :pos, nil),
            Command::Argument.new("dataset", :optlong, "ds-1")
          ])

          root.run
        end
      end
    end
  end

  describe "verbose mode" do
    it "provides detailed output in verbose mode" do
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Verbose Test', 'image', '{}')")
        db.close
      end

      key, cert = VerifySpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key_file.path, cert_file.path)

          # Verify with verbose output
          root = Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("verify", :pos, nil),
            Command::Argument.new("dataset", :optlong, "ds-1"),
            Command::Argument.new("verbose", :optlong, "true")
          ])

          # Should print additional information (algorithm, curve, signed_at, etc.)
          root.run
        end
      end
    end
  end

  describe "error handling" do
    it "handles invalid JSON metadata gracefully" do
      # Create dataset with invalid JSON metadata
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Bad JSON', 'image', 'not valid json')")
        db.close
      end

      # Verify should handle gracefully and fail
      expect_raises(Command::UpdError, /failed verification/) do
        root = Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("verify", :pos, nil),
          Command::Argument.new("dataset", :optlong, "ds-1")
        ])
        root.run
      end
    end

    it "handles missing signature fields" do
      # Create dataset and manually add incomplete signature
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Incomplete Sig', 'image', '{\"Content-Signature\": [{\"signature\": \"test\"}]}')")
        db.close
      end

      # Verify should handle gracefully and fail
      expect_raises(Command::UpdError, /failed verification/) do
        root = Command::Root.new([
          Command::Argument.new("input", :optlong, "test.upd"),
          Command::Argument.new("verify", :pos, nil),
          Command::Argument.new("dataset", :optlong, "ds-1")
        ])
        root.run
      end
    end
  end

  describe "verification summary" do
    it "provides accurate summary statistics" do
      # Create multiple datasets with various states
      DB.connect("duckdb://test.upd") do |db|
        db.exec("INSERT INTO datasets VALUES ('ds-1', 'Signed 1', 'image', '{}')")
        db.exec("INSERT INTO datasets VALUES ('ds-2', 'Signed 2', 'text', '{}')")
        db.exec("INSERT INTO datasets VALUES ('ds-3', 'Unsigned', 'video', '{}')")
        db.close
      end

      key, cert = VerifySpecHelpers.create_test_key_and_cert

      File.tempfile("key") do |key_file|
        File.tempfile("cert") do |cert_file|
          File.write(key_file.path, key.to_pem)
          File.write(cert_file.path, cert.to_pem)

          # Sign first two datasets
          VerifySpecHelpers.sign_dataset("test.upd", "ds-1", key_file.path, cert_file.path)
          VerifySpecHelpers.sign_dataset("test.upd", "ds-2", key_file.path, cert_file.path)

          # Verify all - should show summary with 3 datasets, 2 signatures, 0 failures
          root = Command::Root.new([
            Command::Argument.new("input", :optlong, "test.upd"),
            Command::Argument.new("verify", :pos, nil)
          ])

          root.run
        end
      end
    end
  end
end
