#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_FILE="$PROJECT_DIR/SSHTunel.xcodeproj"
SCHEME="SSHTunel"
CONFIGURATION="${1:-Debug}"
DERIVED_DATA="$PROJECT_DIR/.build"
APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$SCHEME.app"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Error: xcodebuild not found. Install Xcode and command line tools." >&2
  exit 1
fi

if [[ ! -d "$PROJECT_FILE" ]]; then
  echo "Error: project not found at $PROJECT_FILE" >&2
  exit 1
fi

echo "Building $SCHEME ($CONFIGURATION)..."
xcodebuild \
  -project "$PROJECT_FILE" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Error: built app not found at $APP_PATH" >&2
  exit 1
fi

echo "Launching $APP_PATH"
open "$APP_PATH"
