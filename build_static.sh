#!/bin/sh

# Build the Docker image
docker build -t dsb . &&

# Create a temporary container
docker create --name dsbinstance dsb &&

# Ensure ./bin existence
mkdir -p ./bin &&

# Extract the binary from the /output directory
docker cp dsbinstance:/usr/local/bin/datset ./bin/datset-static &&

# Clean up the container
docker rm dsbinstance
