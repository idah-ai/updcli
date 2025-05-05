-- datset v1.0
-- Schema definition.
-- Use SQLite
-- Indexes are optional in the format, but recommended for performant use with datset CLI.

-- This schema is idempotent and can be used to create a new database or
-- update an existing one.

-- Table for batches
-- Note: SQLite does not have ENUM type, using TEXT with CHECK constraint instead.
CREATE TABLE IF NOT EXISTS datasets (
    id TEXT PRIMARY KEY CHECK(length(id) <= 64),
    name TEXT NOT NULL,
    topology TEXT NOT NULL, -- Data topology, ex: imageset, video, etc.
    metadata TEXT           -- Such as allowed annotation types, domain specific data.
) STRICT;

-- Table for media blobs
CREATE TABLE IF NOT EXISTS medias (
    id TEXT PRIMARY KEY,
    key TEXT,                   -- Key referencing the media if the media is a set of files. e.g. image.jpg/small
    blob_data BLOB,             -- Binary data for the media. Can be null, in case of media defined by metadata for example.
    media_type TEXT,            -- Mime type of media, e.g., image/jpeg, video/mp4. Optional, can be NULL.
    metadata TEXT NOT NULL      -- Metadata related to the file.
) STRICT;

-- Set unique on id and key to avoid duplicates
CREATE UNIQUE INDEX IF NOT EXISTS idx_media_id_key ON medias (id, key);

-- Table for entries belonging to a batch
CREATE TABLE IF NOT EXISTS entries (
    id TEXT PRIMARY KEY CHECK(length(id) <= 64),
    dataset_id TEXT NOT NULL REFERENCES datasets(id) ON DELETE CASCADE, -- Changed from UUID
    media_url TEXT NOT NULL,                                            -- Can be an external URL or datset://<media_identifier>
    metadata TEXT
) STRICT;

-- Index on batch_id for faster filtering by batch
CREATE INDEX IF NOT EXISTS idx_entries_dataset_id ON entries (dataset_id);

-- Table for annotations belonging to an entry
CREATE TABLE IF NOT EXISTS annotations (
    id TEXT PRIMARY KEY CHECK(length(id) <= 64),
    entry_id TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE, -- Changed FK type to TEXT
    type TEXT NOT NULL, -- Type of annotation, e.g., bounding_box, segmentation
    definition TEXT NOT NULL, -- Parameters defining the annotation, ex: [x1, y1, x2, y2]
    metadata TEXT NOT NULL -- Other metadata, such as creator, timestamp, comments... JSON format
) STRICT;

-- Index on entry_id for faster filtering by entry
CREATE INDEX IF NOT EXISTS idx_annotations_entry_id ON annotations (entry_id);
-- Index on type for faster filtering by annotation type
CREATE INDEX IF NOT EXISTS idx_annotations_type ON annotations (type);

-- Table for global metadata (key-value store)
CREATE TABLE IF NOT EXISTS metadata (
    key TEXT PRIMARY KEY CHECK(length(key) <= 255),
    value TEXT NOT NULL
) STRICT;

-- Insert default global metadata
INSERT INTO metadata (key, value) VALUES
  ('type', '"datset"'),
  ('version', '"1.0"')
ON CONFLICT (key) DO UPDATE SET value = excluded.value;
