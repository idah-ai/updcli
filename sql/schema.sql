-- datset v1.0
-- Schema definition.
-- Use DuckDB
-- Indexes are optional in the format, but recommended for performant use with datset CLI.

-- This schema is idempotent and can be used to create a new database or
-- update an existing one.

INSTALL JSON;
LOAD JSON;

-- Table for batches
CREATE TABLE IF NOT EXISTS datasets (
    id VARCHAR PRIMARY KEY CHECK(length(id) <= 64),
    name VARCHAR NOT NULL CHECK(length(name) <= 64),
    modality VARCHAR NOT NULL CHECK(length(modality) <= 64), -- Data modality, ex: imageset, video, etc.
    metadata JSON default '{}'           -- Such as allowed annotation types, domain specific data.
);

-- Table for media blobs
CREATE TABLE IF NOT EXISTS medias (
    id VARCHAR NOT NULL CHECK(length(id) <= 64),
    key VARCHAR NOT NULL CHECK(length(key) <= 256),              -- Key referencing the media if the media is a set of files. e.g. image.jpg/small
    blob_data BLOB,                                           -- Binary data for the media. Can be null, in case of media defined by metadata for example.
    media_type VARCHAR CHECK(length(media_type) <= 64),       -- Mime type of media, e.g., image/jpeg, video/mp4. Optional, can be NULL.
    metadata JSON DEFAULT '{}',                                -- Metadata related to the file.
    PRIMARY KEY (id, key)
);

-- Table for entries belonging to a batch
CREATE TABLE IF NOT EXISTS entries (
    id VARCHAR PRIMARY KEY CHECK(length(id) <= 64),
    dataset_id VARCHAR NOT NULL REFERENCES datasets(id) ON DELETE RESTRICT,
    media_url VARCHAR NOT NULL,                                                -- Can be an external URL or datset://<media_identifier>
    metadata JSON DEFAULT '{}'                                              -- Metadata related to the entry, e.g., original filename, source, etc.
);

-- Index on batch_id for faster filtering by batch
CREATE INDEX IF NOT EXISTS idx_entries_dataset_id ON entries (dataset_id);

-- Table for annotations belonging to an entry
CREATE TABLE IF NOT EXISTS annotations (
    id VARCHAR PRIMARY KEY CHECK(length(id) <= 64),
    entry_id VARCHAR NOT NULL REFERENCES entries(id) ON DELETE RESTRICT,
    shape_type VARCHAR NOT NULL CHECK(length(shape_type) <= 64), -- Shape of the annotation, e.g., bounding_box, segmentation
    shape_args JSON NOT NULL,  -- Parameters defining the annotation's shape, ex: [x1, y1, x2, y2]
    annotation JSON NOT NULL,
    metadata JSON DEFAULT '{}' -- Other metadata, such as creator, timestamp, comments... JSON format
);

-- Index on entry_id for faster filtering by entry
CREATE INDEX IF NOT EXISTS idx_annotations_entry_id ON annotations (entry_id);
-- Index on type for faster filtering by annotation type

CREATE INDEX IF NOT EXISTS idx_annotations_type ON annotations (shape_type);

-- Table for global metadata (key-value store)
CREATE TABLE IF NOT EXISTS metadata (
    key VARCHAR PRIMARY KEY CHECK(length(key) <= 64),
    value JSON NOT NULL
);

-- Insert default global metadata
INSERT INTO metadata (key, value) VALUES
  ('Schema-Type', '"Universal Portable Dataset"'),
  ('Schema-Version', '"1.0"'),
  ('Schema-Built-By', '"updcli v1.0"'),
  ('Schema-Flavor', '"None"')
ON CONFLICT (key) DO UPDATE SET value = excluded.value;
