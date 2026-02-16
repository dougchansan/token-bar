#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Building TokenBar..."
swift build

APP_DIR="build/TokenBar.app/Contents/MacOS"
mkdir -p "$APP_DIR"
cp .build/debug/TokenBar "$APP_DIR/TokenBar"

echo "Built: build/TokenBar.app"
echo "Run with: open build/TokenBar.app"
