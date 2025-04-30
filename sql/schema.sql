PRAGMA foreign_keys = ON;
PRAGMA application_id = 0x2fefd315; -- datset

-- datset v1.0
-- Schema definition.
-- Use SQLite
-- Indexes are optional in the format, but recommended for performant use with datset CLI.

-- Table for batches
-- Note: SQLite does not have ENUM type, using TEXT with CHECK constraint instead.
CREATE TABLE batches (
    id TEXT PRIMARY KEY CHECK(length(id) <= 64),
    name TEXT NOT NULL,
    topology TEXT NOT NULL, -- Batch topology, ex: imageset, video, etc.
    metadata TEXT
) STRICT;

-- Table for media blobs
CREATE TABLE medias (
    id TEXT PRIMARY KEY,
    blob_data BLOB, -- Binary data for the media. Can be null, in case of media defined by metadata for example.
    media_type TEXT, -- Mime type of media, e.g., image/jpeg, video/mp4. Optional
    metadata TEXT NOT NULL -- Extra metadata. Useful for compound media types, such as lidar with images
) STRICT;

-- Table for entries belonging to a batch
CREATE TABLE entries (
    id TEXT PRIMARY KEY CHECK(length(id) <= 64),
    batch_id TEXT NOT NULL REFERENCES batches(id) ON DELETE CASCADE, -- Changed from UUID
    media_url TEXT NOT NULL, -- Can be an external URL or datset://<media_identifier>
    metadata TEXT
) STRICT;

-- Index on batch_id for faster filtering by batch
CREATE INDEX idx_entries_batch_id ON entries (batch_id);

-- Table for annotations belonging to an entry
CREATE TABLE annotations (
    id TEXT PRIMARY KEY CHECK(length(id) <= 64),
    entry_id TEXT NOT NULL REFERENCES entries(id) ON DELETE CASCADE, -- Changed FK type to TEXT
    type TEXT NOT NULL, -- Type of annotation, e.g., bounding_box, segmentation
    definition TEXT NOT NULL, -- Parameters defining the annotation, ex: [x1, y1, x2, y2]
    metadata TEXT NOT NULL -- Other metadata, such as creator, timestamp, comments...
) STRICT;

-- Index on entry_id for faster filtering by entry
CREATE INDEX idx_annotations_entry_id ON annotations (entry_id);
-- Index on type for faster filtering by annotation type
CREATE INDEX idx_annotations_type ON annotations (type);

-- Table for global metadata (key-value store)
CREATE TABLE metadata (
    key TEXT PRIMARY KEY CHECK(length(key) <= 255),
    value TEXT NOT NULL
) STRICT;

-- Insert default global metadata
INSERT INTO metadata (key, value) VALUES
('type', '"datset"'),
('version', '"1.0"');
