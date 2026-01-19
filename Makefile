.PHONY: build release clean install test

# Build directory
BUILD_DIR = .build/release
BINARY = claude-notes-bridge

# Build debug version
build:
	swift build

# Build release version (universal binary)
release:
	swift build -c release --arch arm64 --arch x86_64

# Clean build artifacts
clean:
	swift package clean
	rm -rf .build

# Install to /usr/local/bin
install: release
	cp $(BUILD_DIR)/$(BINARY) /usr/local/bin/

# Run tests
test:
	swift test

# Sign the binary (requires Developer ID)
sign: release
	codesign --sign "Developer ID Application" \
		--options runtime \
		--timestamp \
		$(BUILD_DIR)/$(BINARY)

# Create a zip for notarization
zip: sign
	cd $(BUILD_DIR) && zip $(BINARY).zip $(BINARY)

# Show help
help:
	@echo "Available targets:"
	@echo "  build    - Build debug version"
	@echo "  release  - Build universal release binary"
	@echo "  clean    - Clean build artifacts"
	@echo "  install  - Install to /usr/local/bin"
	@echo "  test     - Run tests"
	@echo "  sign     - Code sign the binary"
	@echo "  zip      - Create zip for notarization"
