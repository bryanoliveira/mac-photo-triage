#!/bin/bash
set -euo pipefail

# PhotoTriage Build Script
# Builds the application using Swift Package Manager

echo "=========================================="
echo "Building PhotoTriage"
echo "=========================================="

# Check for macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Error: PhotoTriage is a macOS application and must be built on macOS."
    exit 1
fi

# Check for Swift
if ! command -v swift &> /dev/null; then
    echo "Error: Swift is not installed. Please install Xcode."
    exit 1
fi

# Print Swift version
echo "Swift version:"
swift --version
echo ""

# Build configuration (default: release)
CONFIG="${1:-release}"

echo "Building in $CONFIG mode..."
echo ""

# Clean previous build (optional)
if [[ "${CLEAN:-}" == "true" ]]; then
    echo "Cleaning previous build..."
    swift package clean
fi

# Build the project
if [[ "$CONFIG" == "release" ]]; then
    swift build -c release
else
    swift build
fi

# Check if build succeeded
if [[ $? -eq 0 ]]; then
    echo ""
    echo "=========================================="
    echo "Build successful!"
    echo "=========================================="

    if [[ "$CONFIG" == "release" ]]; then
        echo "Binary location: .build/release/PhotoTriage"
    else
        echo "Binary location: .build/debug/PhotoTriage"
    fi

    echo ""
    echo "To run the app:"
    if [[ "$CONFIG" == "release" ]]; then
        echo "  .build/release/PhotoTriage"
    else
        echo "  .build/debug/PhotoTriage"
    fi
else
    echo ""
    echo "=========================================="
    echo "Build failed!"
    echo "=========================================="
    exit 1
fi
