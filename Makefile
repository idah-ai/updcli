CRYSTAL := crystal
FLAGS := --static \
         --release \
        --link-flags="-L/usr/lib -lduckdb -lstdc++ -lm -lpthread -lz"

SRC_DIR := src
BUILD_DIR := bin
EXECUTABLE := $(BUILD_DIR)/datset
MAIN_SRC := $(SRC_DIR)/main.cr

# Default target
all: build

# Build the executable
build: $(EXECUTABLE)

$(EXECUTABLE): $(MAIN_SRC)
	@mkdir -p $(BUILD_DIR)
	$(CRYSTAL) build $(MAIN_SRC) -o $(EXECUTABLE) $(FLAGS)

# Run the program
run: build
	./$(EXECUTABLE)

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)

.PHONY: all build run clean