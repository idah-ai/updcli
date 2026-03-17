# Stage 1: Build DuckDB static library with musl
FROM alpine:3.19 AS duckdb-builder
WORKDIR /build

ARG DUCKDB_VERSION=v1.3.2

RUN apk add --no-cache \
    g++ \
    git \
    make \
    cmake \
    ninja \
    python3 \
    linux-headers \
    zlib-dev \
    zlib-static

RUN git clone --depth 1 --branch ${DUCKDB_VERSION} https://github.com/duckdb/duckdb && cd duckdb

WORKDIR /build/duckdb

RUN cmake -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_UNITTESTS=OFF \
    -DENABLE_SANITIZER=OFF \
    -DDISABLE_EXTENSION_LOAD=1 \
    -DCORE_EXTENSIONS='icu;json;parquet' \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_CXX_FLAGS="-fPIC" \
    -DCMAKE_C_FLAGS="-fPIC" \
    -B build/release \
    -S .

RUN cmake --build build/release --config Release


# Create a merged static library containing everything
WORKDIR /build/merged
RUN mkdir -p extract && cd extract && \
    echo "=== Extracting all .a files ===" && \
    find /build/duckdb/build/release -name "*.a" -type f -print0 | while IFS= read -r -d '' lib; do \
        echo "Extracting: $lib"; \
        ar x "$lib"; \
    done && \
    echo "=== Creating merged library ===" && \
    ar rcs libduckdb_merged.a *.o && \
    ranlib libduckdb_merged.a && \
    echo "=== Merged library created ===" && \
    ls -lh libduckdb_merged.a

# Stage 2: Build Crystal binary
FROM crystallang/crystal:1.19-alpine AS builder

RUN apk add --no-cache \
    build-base \
    musl-dev \
    linux-headers \
    libstdc++-dev \
    zlib-dev zlib-static \
    gmp-dev gmp-static \
    pcre2-dev pcre2-static \
    gc-dev gc-static \
    openssl-dev openssl-libs-static

# Copy ONLY the merged library
COPY --from=duckdb-builder /build/merged/extract/libduckdb_merged.a /usr/lib/libduckdb.a

# Copy headers
COPY --from=duckdb-builder /build/duckdb/src/include/duckdb.h /usr/include/
COPY --from=duckdb-builder /build/duckdb/src/include/duckdb.hpp /usr/include/
COPY --from=duckdb-builder /build/duckdb/src/include/duckdb /usr/include/duckdb/

RUN mkdir -p /dsb/bin
WORKDIR /dsb

COPY shard.yml ./
COPY shard.lock ./
COPY VERSION ./

RUN crystal -v && shards install --production -v

COPY src ./src
COPY sql ./sql
COPY Makefile ./

# Verify the merged library
RUN echo "=== Merged library size ===" && ls -lh /usr/lib/libduckdb.a

# Build
RUN make static

RUN file bin/updcli && (ldd bin/updcli 2>&1 || true)

FROM alpine:3.19
RUN apk add --no-cache libgcc libstdc++
COPY --from=builder /dsb/bin/updcli /usr/local/bin/updcli
ENTRYPOINT ["/usr/local/bin/updcli"]