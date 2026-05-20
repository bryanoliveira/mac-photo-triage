#!/bin/bash
set -euo pipefail

# PhotoTriage Test Script
# Runs unit tests using Swift Package Manager

echo "=========================================="
echo "Running PhotoTriage Tests"
echo "=========================================="

# Check for macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "Error: PhotoTriage tests must be run on macOS."
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

# Filter for specific test if provided
if [[ -n "${1:-}" ]]; then
    echo "Running specific test: $1"
    echo ""
    swift test --filter "$1"
else
    echo "Running all tests..."
    echo ""
    swift test
fi

# Check if tests succeeded
if [[ $? -eq 0 ]]; then
    echo ""
    echo "=========================================="
    echo "All tests passed!"
    echo "=========================================="
else
    echo ""
    echo "=========================================="
    echo "Some tests failed!"
    echo "=========================================="
    exit 1
fi
