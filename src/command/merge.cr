module Command
  class Merge < Base
    Log = ::Log.for("merge")
    description "Merge another UPD file into this one."

    option "source", "s", "Path to the source UPD file to merge from", required: true, type: :string
    option "strategy", "r", "Conflict resolution strategy: skip (default) or overwrite", default: "skip", type: :string

    def run_impl
      source_path = option("source").not_nil!
      strategy = (option("strategy") || "skip").downcase

      unless File.exists?(source_path)
        raise Command::UpdError.new("Source file not found: #{source_path}", self)
      end

      unless ["skip", "overwrite"].includes?(strategy)
        raise Command::UpdError.new("Invalid strategy '#{strategy}'. Must be 'skip' or 'overwrite'", self)
      end

      db = root.database

      begin
        db.exec("ATTACH '#{source_path}' AS merge_source (READ_ONLY)")

        db.exec("BEGIN TRANSACTION")

        # Insert verb depends on the chosen strategy
        insert_verb = strategy == "overwrite" ? "INSERT OR REPLACE" : "INSERT OR IGNORE"

        # 1. Datasets (no FK dependencies)
        datasets_merged = merge_table(db, insert_verb, "datasets",
          "SELECT id, name, modality, metadata FROM merge_source.datasets")

        # 2. Entries (depends on datasets)
        entries_merged = merge_table(db, insert_verb, "entries",
          "SELECT id, dataset_id, media_url, metadata FROM merge_source.entries")

        # 3. Annotations (depends on entries)
        annotations_merged = merge_table(db, insert_verb, "annotations",
          "SELECT id, entry_id, shape_type, shape_args, category, properties, metadata FROM merge_source.annotations")

        # 4. Medias (composite PK, no FK)
        medias_merged = merge_table(db, insert_verb, "medias",
          "SELECT id, key, blob_data, media_type, metadata FROM merge_source.medias")

        db.exec("COMMIT")

        Log.info { "Merge complete (strategy: #{strategy}):" }
        Log.info { "  datasets:    #{datasets_merged}" }
        Log.info { "  entries:     #{entries_merged}" }
        Log.info { "  annotations: #{annotations_merged}" }
        Log.info { "  medias:      #{medias_merged}" }
      rescue e
        db.exec("ROLLBACK") rescue nil
        raise Command::UpdError.new("Merge failed and was rolled back: #{e.message}", self)
      ensure
        db.exec("DETACH merge_source") rescue nil
      end
    end

    private def merge_table(db, insert_verb : String, table : String, select_sql : String) : String
      before = db.query_one("SELECT COUNT(*) FROM #{table}", as: Int64)
      db.exec("#{insert_verb} INTO #{table} #{select_sql}")
      after = db.query_one("SELECT COUNT(*) FROM #{table}", as: Int64)
      inserted = after - before
      source_count = db.query_one("SELECT COUNT(*) FROM merge_source.#{table}", as: Int64)
      skipped = source_count - inserted
      "#{inserted} inserted, #{skipped} skipped"
    end
  end
end