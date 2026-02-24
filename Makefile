CRYSTAL := crystal
SRC_DIR := src
BUILD_DIR := bin
EXECUTABLE := $(BUILD_DIR)/datset
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

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)

.PHONY: all build run static dynamic info clean