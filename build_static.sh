#!/bin/sh

# Ensure ./bin exists
mkdir -p ./bin

# Build and export the binary using docker buildx
docker buildx build \
  --build-arg DUCKDB_VERSION=v1.3.2 \
  --output type=local,dest=./bin \
  -t dsb .

# Rename the binary (adjust the path as needed)
cp ./bin/usr/local/bin/updcli ./bin/updcli-static
