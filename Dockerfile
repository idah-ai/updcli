# Stage 1: Build the binary
FROM crystallang/crystal:1.16.2-alpine AS builder

# Install SQLite development package
RUN apk add --no-cache sqlite-dev sqlite-static

# Create build directory
RUN mkdir -p /dsb/bin
WORKDIR /dsb

# Copy dependencies first to leverage Docker caching
COPY shard.yml ./
COPY shard.lock ./
RUN crystal -v && shards install --production -v

# Copy source code and build files
COPY src ./src
COPY sql ./sql

# Build the binary
RUN crystal build src/main.cr --static --release --output bin/datset
