# updcli

A command-line interface for creating, managing and signing **Universal Portable Dataset (UPD)** files — a portable dataset container format built on [DuckDB](https://duckdb.org/).

UPD files are single `.upd` (DuckDB) files containing datasets, entries, annotations, and media blobs, with optional ECDSA cryptographic signatures for data integrity verification.

---

## Building

### Requirements

- [Crystal](https://crystal-lang.org/) ≥ 1.16
- [DuckDB](https://duckdb.org/) (shared library for dynamic builds)
- Docker (for static builds only)
- GNU Make

### Dynamic build (development)

```bash
make build
# or simply:
make
```

The binary is written to `./bin/datset`.

### Static build (for distribution)

A fully static binary can be built using Docker and Alpine Linux with musl libc. This compiles DuckDB from source as a static library and links everything into a single portable binary.

```bash
# Using the helper script:
./build_static.sh

# Or using Make:
make static
```

The static binary is extracted to `./bin/datset-static`.

> **Note:** The static build compiles DuckDB from scratch, which takes several minutes on first run.

### Build options

| Target         | Description                      |
| -------------- | -------------------------------- |
| `make build`   | Dynamic release binary           |
| `make static`  | Static release binary via Docker |
| `make dynamic` | Explicit dynamic build           |
| `make clean`   | Remove build artifacts           |
| `make info`    | Show current build configuration |

---

## How it works

### File format

A `.upd` file is a standard DuckDB database. It can be opened with any DuckDB client (Python, CLI, WASM, etc.) in addition to `updcli`.

The core schema contains five tables:

| Table         | Description                                                                 |
| ------------- | --------------------------------------------------------------------------- |
| `metadata`    | Global file-level key/value store (schema version, flavor, etc.)            |
| `datasets`    | Logical dataset containers with a modality (image, text, etc.)              |
| `entries`     | Individual data points belonging to a dataset, each referencing a media URL |
| `annotations` | Labels/shapes attached to entries                                           |
| `medias`      | Binary media blobs stored inside the file, with composite PK `(id, key)`    |

### Command tree

```
datset [--input <file.upd>]
  init                         Initialise a new UPD file
  append [-i <file.jsonl>]     Bulk-import records from a JSONL file
  merge -s <source.upd>        Merge another UPD file into this one

  dataset
    create -n <name> -m <modality>  Create a dataset
    list                            List all datasets
    show -i <id>                    Show a dataset
    update -i <id>                  Update a dataset
    delete -i <id>                  Delete a dataset

  entry
    create -d <dataset_id> -u <url>  Create an entry
    list                             List all entries
    show -i <id>                     Show an entry
    update -i <id>                   Update an entry
    delete -i <id>                   Delete an entry

  annotation
    create -e <entry_id> -t <type> -s <shape_json> -a <annotation_json>
    list
    show -i <id>
    update -i <id>
    delete -i <id>

  media
    create -f <file_path>    Import a file as a media blob
    list                     List all media entries
    show -i <id>             Show media metadata
    update -i <id> -k <key>  Update a media blob
    delete -i <id>           Delete a media entry
    extract -i <id>          Extract a blob back to disk

  sign -k <key.pem> -c <cert.pem>    Sign datasets with ECDSA
  verify                              Verify signatures
```

---

## Usage examples

### Initialise a new file

```bash
datset --input my_data.upd init
```

### Datasets

```bash
# Create
datset --input my_data.upd dataset create --name "Cats vs Dogs" --modality image

# List
datset --input my_data.upd dataset list

# Update (partial — only provided fields change)
datset --input my_data.upd dataset update --id <id> --name "Cats & Dogs"

# Delete
datset --input my_data.upd dataset delete --id <id>
```

### Entries

```bash
# Create with an external URL
datset --input my_data.upd entry create --dataset_id <ds_id> --url https://example.com/img.jpg

# Create with an embedded media reference
datset --input my_data.upd entry create --dataset_id <ds_id> --url datset://my-photo.jpg

# Update the URL
datset --input my_data.upd entry update --id <id> --url https://new.example.com/img.jpg
```

### Annotations

```bash
# Create a bounding box annotation
datset --input my_data.upd annotation create \
  --entry_id <entry_id> \
  --type bbox \
  --shape '{"x":10,"y":20,"w":100,"h":80}' \
  --annotation '{"label":"cat","score":0.95}'

# Update just the annotation value
datset --input my_data.upd annotation update --id <ann_id> \
  --annotation '{"label":"dog","score":0.87}'
```

### Media blobs

```bash
# Import a file (MIME type auto-detected from extension)
datset --input my_data.upd media create --file ./photo.jpg

# Import with a specific key (for multi-resolution variants)
datset --input my_data.upd media create --file ./photo.jpg --id photo-001 --key full
datset --input my_data.upd media create --file ./thumb.jpg --id photo-001 --key thumbnail

# Extract back to disk
datset --input my_data.upd media extract --id <id> --output ./recovered.jpg

# Update blob content
datset --input my_data.upd media update --id <id> --key full --file ./new_photo.jpg
```

### Bulk import (JSONL)

The `append` command reads [JSONL](https://jsonlines.org/) from a file or stdin. Each line is a JSON object with a `command` key (using `:` as separator) and an `args` map:

```jsonl
{"command":"dataset:create","args":{"name":"My Dataset","modality":"image"}}
{"command":"entry:create","args":{"dataset_id":"<ds_id>","url":"https://example.com/1.jpg"}}
{"command":"annotation:create","args":{"entry_id":"<e_id>","type":"bbox","shape":"{\"x\":0}","annotation":"{\"label\":\"cat\"}"}}
```

```bash
# From a file
datset --input my_data.upd append --input records.jsonl

# From stdin
cat records.jsonl | datset --input my_data.upd append
```

The entire operation runs in a single transaction — if any line fails, everything is rolled back.

### Merging UPD files

Combine two UPD files into one. The `--input` file is the **target**; `--source` is the file to merge from. The global `metadata` table (schema version, flavor, etc.) is intentionally not merged — it belongs to the target file.

```bash
# Merge source.upd into target.upd, skipping any conflicting records (default)
datset --input target.upd merge --source source.upd

# Merge and overwrite conflicts with the source version
datset --input target.upd merge --source source.upd --strategy overwrite
```

**Strategies:**

| Strategy         | Behaviour on duplicate primary key   |
| ---------------- | ------------------------------------ |
| `skip` (default) | Target record is preserved           |
| `overwrite`      | Source record replaces target record |

Merges are atomic: if any table fails (e.g. a FK violation), the entire operation is rolled back and the target file is left unchanged.

### ECDSA Signing and Verification

```bash
# Generate a key and self-signed certificate
openssl ecparam -name prime256v1 -genkey -noout -out key.pem
openssl req -new -x509 -key key.pem -out cert.pem -days 365

# Sign all datasets
datset --input my_data.upd sign --key key.pem --cert cert.pem

# Sign a specific dataset
datset --input my_data.upd sign --key key.pem --cert cert.pem --dataset <ds_id>

# Sign with flavor tables included
datset --input my_data.upd sign --key key.pem --cert cert.pem --flavor-tables custom_table

# Verify all signatures
datset --input my_data.upd verify

# Strict mode (validates certificate expiry)
datset --input my_data.upd verify --strict
```

Signatures are stored as JSON in the `metadata` column of each dataset under the `Content-Signature` key. The signing process follows the UPD RFC Section 5.4/5.5 canonical serialisation rules to ensure deterministic, reproducible hashes.

---

## Running the test suite

```bash
# All specs
crystal spec

# A single spec file
crystal spec spec/command/dataset_spec.cr

# With verbose output
crystal spec --verbose
```

Each spec file manages its own isolated `.upd` file and cleans up after itself, so all specs can be run together safely.
