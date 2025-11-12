# Universal Portable Dataset (UPD) File Format

**Status:** 0.2 Beta
**Author:** Yacine Petitprez (yacine.petitprez@ingedata.ai)
**Date:** November 2025

---

## 1. Introduction

### 1.1. The Problem: Data Governance and Portability Headaches

The lack of a standardized, portable dataset format across Artificial Intelligence (AI) pipelines results in significant overhead related to format conversion, loss of critical provenance data (e.g., annotation lifecycle, QC status), and complex data sharing among various actors (annotators, researchers, model developers).

### 1.2. Goal and Scope

This RFC defines the **Universal Portable Dataset (UPD)** file format. The UPD format specifies a mandatory SQL database schema (the UPD Core Schema) and a set of conventions, all encapsulated within a single, high-performance **DuckDB database file**. The primary goal is to ensure data portability, high-performance querying, and end-to-end traceability of dataset entities.

The format is meant to be simple to implement, easy to extend, and compatible with a wide range of tools and programming languages that support DuckDB.

**The UPD format is a container specification and does NOT define the semantics of the contained data.** Like DICOM or other container formats, UPD provides structure for storage and transport, while vendors and users define the meaning and interpretation of the data through Flavors.

### 1.3. Terminology

- **UPD File:** A single DuckDB file containing the database that adheres to this specification.
- **UPD Core Schema:** The mandatory, base set of tables, columns, and constraints defined in Section 3.
- **Actor:** Any entity (human, script, or system) that interacts with the UPD file.
- **Flavor:** A standardized, documented extension of the UPD Core Schema that adds vendor-specific or use-case-specific tables and columns. All UPD files without extensions are considered "Vanilla" flavor.
- **Vendor Prefix:** A namespace identifier (e.g., `idah-`, `acme-`) used to disambiguate vendor-specific values in shared columns like `modality` or `shape_type`.

---

## 2. File Format and Storage Requirements

The UPD format leverages DuckDB's capabilities as a portable analytical data management system.

- The file **MUST** be stored as a single **DuckDB file**.
- The file extension **SHOULD** be `.upd` or `.duckdb`.
- The file **MUST** be openable and queryable using any standard, unmodified DuckDB client binding (Python, C++, WASM, etc.).

---

## 3. UPD Core Schema Specification

The following schema defines the mandatory structure. All data types and constraints are tailored for optimal compatibility and performance across DuckDB environments.

### 3.1. Data Type Enforcement

To maximize portability, especially across different DuckDB bindings and versions:

- **JSON Content:** All columns intended to store JSON data **MUST** use the `VARCHAR` type. This ensures the data is treated as a simple text string, maximizing compatibility, with JSON parsing delegated to client libraries or DuckDB's built-in `JSON_*` functions.
- **Key Lengths:** Key columns **MUST** enforce maximum length constraints (`CHECK(length(...) <= X)`) for predictable indexing performance.
- **Primary Keys:** Primary keys (`id`) in `datasets`, `entries`, and `annotations` **SHOULD** be generated using **UUIDv7** to enhance lifecycle traceability.

### 3.2. `metadata` Table (Global)

This table stores file-level configuration and integrity information.

```sql
CREATE TABLE IF NOT EXISTS metadata (
    key VARCHAR NOT NULL PRIMARY KEY CHECK(length(key) <= 64),
    value VARCHAR NOT NULL -- JSON stored as VARCHAR
);
```

#### 3.2.1. Global Metadata Key Requirements

Keys **ARE RECOMMENDED TO** follow the `Camel-Case-With-Hyphens` convention (e.g., `Schema-Version`).

| Key | Status | Description |
|-----|--------|-------------|
| `Authored-By` | **OPTIONAL** | Email of the Actor or URL of the organization who created/maintained the UPD file. |
| `Schema-Type` | **REQUIRED** | **MUST** be set to `"Universal Portable Dataset"`. |
| `Schema-Version` | **REQUIRED** | The version of the UPD Core Schema (e.g., `"1.0"`). |
| `Schema-Built-By` | **RECOMMENDED** | Identifies the tool and version that created the file (e.g., `"updcli v1.0.0"`). |
| `Schema-Flavor` | **OPTIONAL** | The name of any standardized extension applied. **SHOULD** be `"Vanilla"` by default. |
| `Schema-Flavor-URL` | **OPTIONAL** | When not `"Vanilla"`, a URL pointing to the flavor documentation. |

### 3.3. `datasets` Table

Defines logical groupings of data.

A dataset **MUST** represent a coherent collection of data points sharing the same modality (e.g., images, text, audio).

```sql
CREATE TABLE IF NOT EXISTS datasets (
    id VARCHAR NOT NULL PRIMARY KEY CHECK(length(id) <= 64),
    name VARCHAR NOT NULL CHECK(length(name) <= 64),
    modality VARCHAR NOT NULL CHECK(length(modality) <= 64),
    metadata VARCHAR DEFAULT '{}' -- JSON stored as VARCHAR
);
```

#### 3.3.1. Dataset Modality

The `modality` column **SHOULD** use a vendor prefix (e.g., `"idah-image"`, `"idah-video"`, `"acme-lidar"`) to unambiguously communicate the shape and type of data. Since UPD is a container format and does not define data semantics, modality values are always vendor-specific. There is no central registry of modality values.

#### 3.3.2. Dataset Metadata

The `metadata` column stores dataset-level information as a JSON string. The following keys are defined:

| Key | Status | Description |
|-----|--------|-------------|
| `Dataset-Specification-URL` | **RECOMMENDED** | URL pointing to detailed dataset documentation defining the modality semantics. |
| `Content-Signature` | **OPTIONAL** | JSON array containing one or more digital signatures for this dataset. See Section 5 for details. |
| `Created-At` | **RECOMMENDED** | ISO 8601 timestamp of dataset creation. |
| `Updated-At` | **RECOMMENDED** | ISO 8601 timestamp of last modification. |
| `Created-By` | **RECOMMENDED** | Email or identifier of the Actor who created the dataset. |

### 3.4. `medias` Table

Stores media blobs or references for media that is local to the UPD file.

The `medias` table **MUST** use a composite primary key `(id, key)` to support datasets where media items consist of multiple files.

```sql
CREATE TABLE IF NOT EXISTS medias (
    id VARCHAR NOT NULL CHECK(length(id) <= 64),
    key VARCHAR NOT NULL CHECK(length(key) <= 256),
    blob_data BLOB,
    media_type VARCHAR CHECK(length(media_type) <= 64),
    metadata VARCHAR DEFAULT '{}', -- JSON stored as VARCHAR
    PRIMARY KEY (id, key)
);
```

#### 3.4.1. Media Table Conventions

- **`blob_data`:** **CAN** be NULL, indicating that the media is stored externally or consists solely of metadata (e.g., when media confidentiality is critical and files are stored in cold storage).
- **`media_type`:** **SHOULD** use standard MIME types (e.g., `image/jpeg`, `video/mp4`, `application/octet-stream`).
- **`key`:**
  - If the media is a single file, `key` **MUST** be set to an empty string `''`.
  - If the media consists of multiple related files (e.g., map tiles, multi-band satellite imagery, video frames), each file **MUST** have a distinct `key` value while sharing the same `id`.

#### 3.4.2. Composite Key Example: Map Tiles

A tiled map dataset where each map consists of multiple image tiles:

| id | key | blob_data | media_type |
|---|---|---|---|
| `map-001` | `00,00.png` | `<binary>` | `image/png` |
| `map-001` | `00,01.png` | `<binary>` | `image/png` |
| `map-001` | `01,00.png` | `<binary>` | `image/png` |
| `map-002` | `00,00.png` | `<binary>` | `image/png` |

In this example, all tiles for `map-001` share the same `id` but have different `key` values to identify each tile.

### 3.5. `entries` Table

Represents individual media entries (e.g., an image, a video, a document), linking a dataset with media location.

```sql
CREATE TABLE IF NOT EXISTS entries (
    id VARCHAR NOT NULL PRIMARY KEY CHECK(length(id) <= 64),
    dataset_id VARCHAR NOT NULL REFERENCES datasets(id) ON DELETE RESTRICT,
    media_url VARCHAR NOT NULL,
    metadata VARCHAR DEFAULT '{}' -- JSON stored as VARCHAR
);

CREATE INDEX IF NOT EXISTS idx_entries_dataset_id ON entries (dataset_id);
```

#### 3.5.1. Foreign Key Constraints

- **`dataset_id`:** The `ON DELETE RESTRICT` constraint is **REQUIRED** to prevent accidental deletion of datasets that have associated entries.

#### 3.5.2. Media URL Format

The `media_url` column **MUST** follow one of these formats:

- **External Media:** Uses standard URL schemes (e.g., `https://example.com/image.jpg`, `s3://bucket/key`, `file:///path/to/file`).
- **Internal Media (Local):**
  - **Single file:** `local:<id>` where `<id>` references a `medias.id` with an empty string `key` (`''`).
  - **Multi-file composite:** `local:<id>` where `<id>` references all rows in `medias` with that `id`. The entry represents the logical aggregation of all files with that `id`.

**Note:** An entry references media by `id` only. The `key` component is internal to the `medias` table structure and is not exposed in the `media_url` format. Client applications are responsible for understanding how to reconstruct composite media from multiple `medias` rows sharing the same `id`.

#### 3.5.3. Entry Metadata

The `metadata` column stores entry-level information as a JSON string. Recommended keys include:

| Key | Status | Description |
|-----|--------|-------------|
| `Created-At` | **RECOMMENDED** | ISO 8601 timestamp of entry creation. |
| `Updated-At` | **RECOMMENDED** | ISO 8601 timestamp of last modification. |
| `Created-By` | **RECOMMENDED** | Email or identifier of the Actor who created the entry. |

### 3.6. `annotations` Table

Stores structured annotations for an entry.

```sql
CREATE TABLE IF NOT EXISTS annotations (
    id VARCHAR NOT NULL PRIMARY KEY CHECK(length(id) <= 64),
    entry_id VARCHAR NOT NULL REFERENCES entries(id) ON DELETE RESTRICT,
    shape_type VARCHAR NOT NULL CHECK(length(shape_type) <= 64),
    shape_args VARCHAR NOT NULL,  -- JSON stored as VARCHAR (e.g., bounding box coordinates)
    annotation VARCHAR NOT NULL,  -- JSON stored as VARCHAR (e.g., class labels, confidence scores)
    metadata VARCHAR DEFAULT '{}'  -- JSON stored as VARCHAR (lifecycle info)
);

CREATE INDEX IF NOT EXISTS idx_annotations_entry_id ON annotations (entry_id);
CREATE INDEX IF NOT EXISTS idx_annotations_shape_type ON annotations (shape_type);
```

#### 3.6.1. Foreign Key Constraints

- **`entry_id`:** The `ON DELETE RESTRICT` constraint is **REQUIRED** to prevent accidental deletion of entries that have associated annotations.

#### 3.6.2. Shape Type and Arguments

- **`shape_type`:** **SHOULD** use vendor-prefixed strings (e.g., `"idah-video-bounding-box"`, `"acme-polygon"`, `"vendor-point"`). It is the vendor's responsibility to document the expected `shape_args` format for each shape type.
- **`shape_args`:** **MUST** be a JSON string defining the shape parameters. The structure is vendor-specific and tied to the `shape_type`.

**Example:**
```json
{
  "shape_type": "idah-bounding-box",
  "shape_args": "{\"x\": 100, \"y\": 200, \"width\": 50, \"height\": 75}",
  "annotation": "{\"class\": \"person\", \"confidence\": 0.95}"
}
```

#### 3.6.3. Annotation Metadata

The `metadata` column stores annotation-level information as a JSON string. Recommended keys include:

| Key | Status | Description |
|-----|--------|-------------|
| `Created-At` | **RECOMMENDED** | ISO 8601 timestamp of annotation creation. |
| `Updated-At` | **RECOMMENDED** | ISO 8601 timestamp of last modification. |
| `Created-By` | **RECOMMENDED** | Email or identifier of the Actor who created the annotation. |
| `Confidence` | **RECOMMENDED** | Numerical score (0.0-1.0) if generated by an AI model. |
| `QC-Status` | **RECOMMENDED** | Status of any Quality Control review (e.g., `"Passed"`, `"Flagged"`, `"Rejected"`). |
| `QC-Reviewed-By` | **OPTIONAL** | Email or identifier of the QC reviewer. |
| `QC-Reviewed-At` | **OPTIONAL** | ISO 8601 timestamp of QC review. |

---

## 4. Extensibility Through Flavors

The UPD format is designed to be extensible while guaranteeing full compatibility with tools that only understand the Core Schema.

### 4.1. What is a Flavor?

A **Flavor** is a documented extension of the UPD Core Schema. Flavors allow vendors and users to add domain-specific or workflow-specific features without breaking compatibility with the core format.

### 4.2. Flavor Rules

- **Adding Tables:** A Flavor **MAY** add new tables to the database.
- **Adding Columns:** A Flavor **MAY** add new columns to existing Core Schema tables.
- **Core Schema Integrity:** The existing tables, columns, and constraints of the UPD Core Schema **MUST NOT** be modified or deleted.
- **Tool Behavior:** Compliant tools **SHOULD** ignore columns and tables they do not recognize, allowing graceful degradation.
- **Naming Convention:** Flavor-specific tables and columns **SHOULD** use vendor prefixes to avoid naming collisions.

### 4.3. Declaring a Flavor

Any tool applying a Flavor **MUST** update the global `metadata` table:

- Set `Schema-Flavor` to a non-`"Vanilla"` value (e.g., `"IDAH-Medical-v1"`, `"Acme-Satellite-v2"`).
- **SHOULD** set `Schema-Flavor-URL` to point to public documentation describing the Flavor.

### 4.4. Flavor Example: Adding a Comments Table

A vendor might add a `comments` table to support annotation review workflows:

```sql
CREATE TABLE IF NOT EXISTS idah_comments (
    id VARCHAR NOT NULL PRIMARY KEY,
    annotation_id VARCHAR NOT NULL REFERENCES annotations(id) ON DELETE RESTRICT,
    comment_text VARCHAR NOT NULL,
    created_by VARCHAR,
    created_at VARCHAR
);
```

This table is part of the "IDAH-Review-v1" Flavor and would be documented at the URL specified in `Schema-Flavor-URL`.

---

## 5. Digital Signatures and Integrity Verification

UPD supports optional cryptographic signatures at the **dataset level** to ensure data integrity and authenticity. Signatures are stored in the `datasets.metadata` column under the `Content-Signature` key.

### 5.1. Why Dataset-Level Signatures?

- **Granular Trust:** Different datasets within a single UPD file may come from different sources or partners. Dataset-level signatures allow each dataset to be independently verified.
- **File-Level Signing:** While the entire UPD file could be signed as a bitstream (e.g., using GPG), that approach is outside the scope of this RFC. UPD focuses on logical, semantic signatures of dataset content.
- **Aggregation Support:** A single UPD file may aggregate datasets from multiple vendors or projects, each with their own signing authority.

### 5.2. Signature Scope

A signature covers:

1. **Core Data Tables:** The `entries` and `annotations` tables (filtered to rows belonging to the signed dataset).
2. **Flavor Tables (Optional):** Any additional custom tables specified in the `signedFlavorTables` array.
3. **Schema Definition:** A hash of the CREATE TABLE statements for all tables included in the signature.

Signatures do **NOT** cover:

- The global `metadata` table
- The `datasets` table itself (to avoid circular dependencies)
- The `medias` table (media integrity should be verified separately using media_type-specific checksums)

### 5.3. Content-Signature JSON Structure

The `Content-Signature` key in `datasets.metadata` **MUST** be a JSON array. Each element represents one signature and **MUST** contain:

```json
{
  "signature": "<base64-encoded ECDSA signature>",
  "dataHashAlgorithm": "<hash algorithm name>",
  "dataHash": "<hex-encoded hash of the data payload>",
  "schemaHash": "<hex-encoded hash of the schema>",
  "certificate": "<base64-encoded X.509 certificate>",
  "curve": "<ECDSA curve name>",
  "signedAt": "<ISO 8601 timestamp>",
  "signedFlavorTables": ["<table_name_1>", "<table_name_2>"]
}
```

#### 5.3.1. Field Definitions

| Field | Required | Description |
|-------|----------|-------------|
| `signature` | **REQUIRED** | Base64-encoded ECDSA signature of the `dataHash`. |
| `dataHashAlgorithm` | **REQUIRED** | Hash algorithm used (e.g., `"SHA256"`, `"SHA512"`). **RECOMMENDED:** `"SHA256"`. |
| `dataHash` | **REQUIRED** | Hex-encoded hash of the canonical data payload (see Section 5.4). |
| `schemaHash` | **REQUIRED** | Hex-encoded hash of the CREATE TABLE statements for all signed tables, concatenated in alphabetical order by table name, separated by newlines. |
| `certificate` | **REQUIRED** | Base64-encoded X.509 certificate containing the public key used to verify the signature. |
| `curve` | **REQUIRED** | ECDSA curve used for signing (e.g., `"secp256r1"`, `"secp256k1"`). **RECOMMENDED:** `"secp256r1"`. |
| `signedAt` | **REQUIRED** | ISO 8601 timestamp when the signature was created. |
| `signedFlavorTables` | **OPTIONAL** | Array of table names (strings) for any Flavor tables included in the signature. Empty array or omitted if only Core tables are signed. |

### 5.4. Canonical Data Payload Serialization

To ensure that every Actor generates an identical cryptographic hash for the data payload, the serialization process **MUST** adhere to the following strict, canonical order. This order guarantees determinism regardless of the underlying DuckDB physical storage layout.

The final hash input is a **single, concatenated byte stream** formed by serializing tables one after another.

#### 5.4.1. Table Order (Data Payload Scope)

The tables **MUST** be serialized and concatenated in this exact order:

1. **`entries`** table (Core) — filtered to `WHERE dataset_id = <signed_dataset_id>`
2. **`annotations`** table (Core) — filtered to `WHERE entry_id IN (SELECT id FROM entries WHERE dataset_id = <signed_dataset_id>)`
3. **Flavor Tables** (Optional): Any additional custom tables listed in the `signedFlavorTables` array, serialized in **alphabetical order** by table name.

#### 5.4.2. Row Order (Within Each Table)

For each table being serialized:

- Rows **MUST** be selected and sorted by the table's **Primary Key** (`id` or composite key) in **ascending (ASC) lexicographic order**.

#### 5.4.3. Column Order (Within Each Row)

For each row being serialized:

- Columns **MUST** be serialized in the order they appear in the table's `CREATE TABLE` statement (the **Ordinal Position**). This includes all custom columns added by a Flavor.

#### 5.4.4. Data Type Serialization

All data values **MUST** be converted to a canonical UTF-8 string representation before serialization. This ensures absolute determinism across all platforms.

| Data Type Category | DuckDB Types | Canonical String Representation |
|-------------------|--------------|--------------------------------|
| **Strings** | `VARCHAR` | Raw UTF-8 bytes. The string is used as-is. |
| **Binary Data** | `BLOB` | Raw binary bytes. The data is used as-is. |
| **Integers** | `TINYINT`, `SMALLINT`, `INTEGER`, `BIGINT`, `HUGEINT` (and unsigned variants) | Decimal string (UTF-8). Example: `12345`. Use `CAST(column AS VARCHAR)`. |
| **Floating Point** | `FLOAT`, `DOUBLE`, `DECIMAL` | Canonical string (UTF-8). Must handle special values: `NaN`, `Infinity`, `-Infinity`. Use `CAST(column AS VARCHAR)`. |
| **Timestamp** | `TIMESTAMP`, `TIMESTAMPTZ` | ISO 8601 string (UTF-8). Format: `YYYY-MM-DDTHH:MM:SS.ffffffZ`. **MUST** be converted to UTC (`Z` timezone). Use DuckDB's `to_iso8601(column)` or `strftime(column, '%Y-%m-%dT%H:%M:%S.%fZ')`. |
| **Date / Time** | `DATE`, `TIME`, `TIMETZ` | ISO 8601 string (UTF-8). `YYYY-MM-DD` for dates, `HH:MM:SS.ffffff` for times. |
| **Boolean** | `BOOLEAN` | Lowercase string (UTF-8). **MUST** be either `"true"` or `"false"`. |
| **UUID** | `UUID` | Canonical 36-character format (UTF-8). Example: `a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11`. |
| **NULL Value** | `NULL` (any type) | The fixed, non-escaped ASCII byte sequence: `\x00NULL\x00` |

#### 5.4.5. Delimiters

- **Column Delimiter:** Columns within a single row **MUST** be separated by the fixed ASCII byte sequence: `\x00COL\x00` (i.e., `\x00` + `C` + `O` + `L` + `\x00`).
- **Row Delimiter:** Rows **MUST** be separated by the fixed ASCII byte sequence: `\x00ROW\x00` (i.e., `\x00` + `R` + `O` + `W` + `\x00`).
- **Table Delimiter:** When multiple tables are included, tables **MUST** be separated by the fixed ASCII byte sequence: `\x00TABLE\x00` (i.e., `\x00` + `T` + `A` + `B` + `L` + `E` + `\x00`).

#### 5.4.6. Concrete Serialization Example

Assume we are signing dataset `ds-001` which has the following data:

**`entries` table (filtered to `dataset_id = 'ds-001'`):**
| id | dataset_id | media_url | metadata |
|---|---|---|---|
| `e-002` | `ds-001` | `local:m-002` | `{"cby":"bob"}` |
| `e-001` | `ds-001` | `https://example.com/img.jpg` | `{"cby":"alice"}` |

**`annotations` table (filtered to entries in `ds-001`):**
| id | entry_id | shape_type | shape_args | annotation | metadata |
|---|---|---|---|---|---|
| `a-001` | `e-001` | `box` | `{"x":0}` | `{"class":"cat"}` | `{}` |

**Serialization Process:**

1. **Table Order:** `entries` first, then `annotations`.
2. **Row Order:** Within `entries`, rows are sorted by `id` ASC: `e-001`, then `e-002`.
3. **Column Order:** Columns are serialized in CREATE TABLE order: `id`, `dataset_id`, `media_url`, `metadata`.

**Resulting Byte Stream (Conceptual):**

```
[entries table]
  [row e-001: id] COL [dataset_id] COL [media_url] COL [metadata] ROW
  [row e-002: id] COL [dataset_id] COL [media_url] COL [metadata]
TABLE
[annotations table]
  [row a-001: id] COL [entry_id] COL [shape_type] COL [shape_args] COL [annotation] COL [metadata]
```

**Resulting Byte Stream (Actual, with hex for delimiters):**

```
e-001\x00COL\x00ds-001\x00COL\x00https://example.com/img.jpg\x00COL\x00{"cby":"alice"}\x00ROW\x00e-002\x00COL\x00ds-001\x00COL\x00local:m-002\x00COL\x00{"cby":"bob"}\x00TABLE\x00a-001\x00COL\x00e-001\x00COL\x00box\x00COL\x00{"x":0}\x00COL\x00{"class":"cat"}\x00COL\x00{}
```

This entire byte sequence is then hashed using the algorithm specified in `dataHashAlgorithm` to produce the `dataHash`.

### 5.5. Schema Hash Computation

The `schemaHash` is computed by:

1. Collecting the `CREATE TABLE` statements for all tables included in the signature (`entries`, `annotations`, and any tables listed in `signedFlavorTables`).
2. Normalizing each statement by removing comments and collapsing whitespace.
3. Sorting the statements **alphabetically by table name**.
4. Concatenating them with a single newline character (`\n`) between each statement.
5. Hashing the resulting string using the algorithm specified in `dataHashAlgorithm`.

**Example:**
```sql
CREATE TABLE annotations (id VARCHAR NOT NULL PRIMARY KEY CHECK(length(id) <= 64), entry_id VARCHAR NOT NULL REFERENCES entries(id) ON DELETE RESTRICT, shape_type VARCHAR NOT NULL CHECK(length(shape_type) <= 64), shape_args VARCHAR NOT NULL, annotation VARCHAR NOT NULL, metadata VARCHAR DEFAULT '{}');
CREATE TABLE entries (id VARCHAR NOT NULL PRIMARY KEY CHECK(length(id) <= 64), dataset_id VARCHAR NOT NULL REFERENCES datasets(id) ON DELETE RESTRICT, media_url VARCHAR NOT NULL, metadata VARCHAR DEFAULT '{}');
```

(Sorted alphabetically: `annotations`, then `entries`, separated by `\n`, then hashed.)

### 5.6. Signing Process

The signing process involves:

1. **Generate Data Payload:** Serialize the data payload as described in Section 5.4.
2. **Compute Data Hash:** Hash the byte stream using the chosen hash algorithm (e.g., SHA256).
3. **Compute Schema Hash:** Hash the CREATE TABLE statements as described in Section 5.5.
4. **Sign Data Hash:** Use ECDSA with the chosen curve (e.g., secp256r1) to sign the `dataHash`.
5. **Encode Signature:** Base64-encode the signature.
6. **Build Content-Signature JSON:** Create a JSON object with all required fields.
7. **Store in Dataset Metadata:** Add the JSON object to the `Content-Signature` array in `datasets.metadata`.

### 5.7. Verification Process

The verification process involves:

1. **Extract Signature:** Parse the `Content-Signature` JSON from `datasets.metadata`.
2. **Regenerate Data Payload:** Serialize the current data payload exactly as described in Section 5.4.
3. **Compute Current Data Hash:** Hash the serialized data using the algorithm specified in `dataHashAlgorithm`.
4. **Compare Data Hashes:** Verify that the computed hash matches the `dataHash` in the signature.
5. **Regenerate Schema Hash:** Compute the schema hash as described in Section 5.5.
6. **Compare Schema Hashes:** Verify that the computed schema hash matches the `schemaHash` in the signature.
7. **Verify Signature:** Use the public key from the `certificate` to verify the ECDSA signature of the `dataHash`.
8. **Validate Certificate:** Optionally verify the X.509 certificate chain against a trusted root CA.

### 5.8. Multiple Signatures

A dataset **MAY** have multiple signatures in the `Content-Signature` array, for example:

- Co-signing by multiple parties
- Re-signing after schema changes (with different `signedFlavorTables`)
- Signing with different cryptographic algorithms for compatibility

### 5.9. Tooling

The reference CLI tool `updcli` provides commands for signing and verifying datasets:

```bash
updcli --db=<file.upd> sign --dataset=<dataset_id> --key=<private_key.pem>
updcli --db=<file.upd> verify --dataset=<dataset_id>
```

---

## 6. Complete Example

### 6.1. Dataset with Signature

**Global Metadata:**
| key | value |
|-----|-------|
| `Schema-Type` | `"Universal Portable Dataset"` |
| `Schema-Version` | `"1.0"` |
| `Schema-Flavor` | `"Vanilla"` |

**Datasets:**
| id | name | modality | metadata |
|---|---|---|---|
| `ds-001` | `"Medical Images Q4 2025"` | `"idah-dicom"` | `{"Dataset-Specification-URL": "https://idah.ai/specs/dicom", "Content-Signature": [<signature_json>]}` |

**Content-Signature JSON (in `datasets.metadata`):**
```json
[
  {
    "signature": "MEQCIH2jD0d4Fq+3kL...",
    "dataHashAlgorithm": "SHA256",
    "dataHash": "a1b2c3d4e5f67890abcdef...",
    "schemaHash": "1a2b3c4d5e6f7890abcdef...",
    "certificate": "MIIDezCCAmOgAwIBAgIU...",
    "curve": "secp256r1",
    "signedAt": "2025-11-10T15:30:00Z",
    "signedFlavorTables": []
  }
]
```

**Entries:**
| id | dataset_id | media_url | metadata |
|---|---|---|---|
| `e-001` | `ds-001` | `local:m-001` | `{"Created-At": "2025-11-01T10:00:00Z", "Created-By": "alice@example.com"}` |

**Medias:**
| id | key | blob_data | media_type | metadata |
|---|---|---|---|---|
| `m-001` | `''` | `<binary DICOM data>` | `application/dicom` | `{}` |

**Annotations:**
| id | entry_id | shape_type | shape_args | annotation | metadata |
|---|---|---|---|---|---|
| `a-001` | `e-001` | `idah-region` | `{"roi": [0,0,512,512]}` | `{"finding": "nodule", "confidence": 0.89}` | `{"Created-By": "model-v2", "QC-Status": "Passed"}` |

---

## 7. Recommendations and Best Practices

### 7.1. UUIDv7 for Primary Keys

Use UUIDv7 for all `id` columns in `datasets`, `entries`, and `annotations`. UUIDv7 includes timestamp information, which aids in lifecycle traceability and debugging.

ULID is an acceptable alternative if UUIDv7 is not feasible. Avoid sequential integer IDs to prevent collisions in distributed systems.

### 7.2. Always Include Metadata

Populate `Created-At`, `Updated-At`, and `Created-By` fields consistently across all entities to enable comprehensive audit trails.

### 7.3. Document Your Flavor

If you extend the Core Schema, publish clear documentation at the URL specified in `Schema-Flavor-URL`. Include:
- New table schemas
- New column descriptions
- Expected JSON structures for custom fields
- Example data

### 7.4. Media Integrity

While UPD signatures cover data tables, media integrity should be verified separately:
- Store checksums in `medias.metadata` (e.g., `{"SHA256": "<hash>"}`)
- Use media_type-specific integrity tools for validation

---

## 8. Future Considerations

### 8.1. Compression

Universal Portable Dataset files **MAY** support compression using DuckDB's built-in compression features. Future versions of this specification may define recommended compression algorithms and settings for optimal performance.

### 8.2. Encryption

Future versions may define conventions for encrypting sensitive data within UPD files, potentially at the dataset or entry level.

### 8.3. Standardized Flavors Registry

A community-maintained registry of common Flavors could improve interoperability.

### 8.4. Streaming APIs

Future specifications may define streaming protocols for accessing UPD files over HTTP or other network protocols without downloading the entire file.

---

## 9. Appendix A: Algorithm Recommendations

| Purpose | Recommended | Acceptable | Not Recommended |
|---------|-------------|------------|-----------------|
| **Hash Algorithm** | SHA256 | SHA512, SHA3-256 | MD5, SHA1 |
| **ECDSA Curve** | secp256r1 (P-256) | secp384r1 (P-384), secp256k1 | Custom curves |
| **Primary Key Format** | UUIDv7, ULID | UUIDv4 | Sequential integers |

---

## 10. Changelog

### Version 0.2 Beta (November 2025)
- Clarified that UPD is a container format and does not define data semantics
- Added detailed section on Flavors and extensibility
- Clarified composite key usage in `medias` table with concrete examples
- Specified that `media_url` should references only the `id`, not the `key` component
- Added algorithm recommendations
- Added complete serialization and signature examples
- Reorganized sections for better logical flow

### Version 0.1 Beta (November 2025)
- Initial draft