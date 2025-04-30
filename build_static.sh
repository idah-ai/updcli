#!/bin/sh

# Build the Docker image
docker build -t dsb . &&

# Create a temporary container
docker create --name dsbinstance dsb &&

# Extract the binary from the /output directory
docker cp dsbinstance:/dsb/bin/datset ./bin/datset-static &&

# Clean up the container
docker rm dsbinstance
