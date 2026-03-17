CRYSTAL := crystal
SRC_DIR := src
BUILD_DIR := bin
EXECUTABLE := $(BUILD_DIR)/updcli
MAIN_SRC := $(SRC_DIR)/main.cr

# Build type: set STATIC=1 for static build, otherwise dynamic
STATIC ?= 0

# Base flags
BASE_FLAGS := --release

# Configure flags based on build type
ifeq ($(STATIC),1)
    FLAGS := $(BASE_FLAGS) --static --link-flags="-L/usr/lib -lduckdb -lstdc++ -lm -lpthread"
    BUILD_TYPE := static
else
    FLAGS := $(BASE_FLAGS)
    BUILD_TYPE := dynamic
endif

# Default target
all: build

# Build the executable
build: $(EXECUTABLE)

$(EXECUTABLE): $(MAIN_SRC)
	@mkdir -p $(BUILD_DIR)
	@echo "Building $(BUILD_TYPE) binary..."
	$(CRYSTAL) build $(MAIN_SRC) -o $(EXECUTABLE) $(FLAGS)
	@echo "Build complete: $(EXECUTABLE) ($(BUILD_TYPE))"

# Run the program
run: build
	./$(EXECUTABLE)

# Build static binary explicitly
static:
	@$(MAKE) build STATIC=1

# Build dynamic binary explicitly
dynamic:
	@$(MAKE) build STATIC=0

# Show build information
info:
	@echo "Build Configuration:"
	@echo "  STATIC=$(STATIC)"
	@echo "  BUILD_TYPE=$(BUILD_TYPE)"
	@echo "  FLAGS=$(FLAGS)"

# Validate VERSION, compare with latest tag, create and push vX.Y.Z tag.
release:
	@# --- Read VERSION file ---
	@if [ ! -f VERSION ]; then \
		echo "Error: VERSION file not found"; exit 1; \
	fi
	@VERSION=$$(cat VERSION | tr -d '[:space:]'); \
	if [ -z "$$VERSION" ]; then \
		echo "Error: VERSION file is empty"; exit 1; \
	fi; \
	\
	# --- Validate strict semver X.Y.Z (no prefix, no pre-release) --- \
	if ! echo "$$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$$'; then \
		echo "Error: '$$VERSION' is not valid semver — expected X.Y.Z (e.g. 1.2.3)"; exit 1; \
	fi; \
	\
	# --- Compare against latest git tag --- \
	LATEST_TAG=$$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//'); \
	if [ -n "$$LATEST_TAG" ]; then \
		NEW_MAJOR=$$(echo "$$VERSION"    | cut -d. -f1); \
		NEW_MINOR=$$(echo "$$VERSION"    | cut -d. -f2); \
		NEW_PATCH=$$(echo "$$VERSION"    | cut -d. -f3); \
		OLD_MAJOR=$$(echo "$$LATEST_TAG" | cut -d. -f1); \
		OLD_MINOR=$$(echo "$$LATEST_TAG" | cut -d. -f2); \
		OLD_PATCH=$$(echo "$$LATEST_TAG" | cut -d. -f3); \
		IS_GREATER=0; \
		if   [ "$$NEW_MAJOR" -gt "$$OLD_MAJOR" ]; then IS_GREATER=1; \
		elif [ "$$NEW_MAJOR" -eq "$$OLD_MAJOR" ] && [ "$$NEW_MINOR" -gt "$$OLD_MINOR" ]; then IS_GREATER=1; \
		elif [ "$$NEW_MAJOR" -eq "$$OLD_MAJOR" ] && [ "$$NEW_MINOR" -eq "$$OLD_MINOR" ] && [ "$$NEW_PATCH" -gt "$$OLD_PATCH" ]; then IS_GREATER=1; \
		fi; \
		if [ "$$IS_GREATER" -eq 0 ]; then \
			echo "Error: VERSION $$VERSION must be greater than latest tag $$LATEST_TAG"; exit 1; \
		fi; \
	fi; \
	\
	# --- Tag and push --- \
	echo "Tagging v$$VERSION..."; \
	git tag "v$$VERSION" || { echo "Error: failed to create tag v$$VERSION"; exit 1; }; \
	git push origin "v$$VERSION" || { git tag -d "v$$VERSION"; echo "Error: push failed — tag removed locally"; exit 1; }; \
	echo "Done — v$$VERSION tagged and pushed. The release workflow will start shortly."

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)

.PHONY: all build run static dynamic info release clean
