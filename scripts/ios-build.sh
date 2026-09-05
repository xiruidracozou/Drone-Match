#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local
# Build the target directly: works with an installed SDK even when Xcode's
# scheme destination resolver demands a newer simulator runtime.
xcodebuild -project apps/ios/DroneMatch.xcodeproj -target DroneMatch \
  -configuration Debug -sdk iphonesimulator ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- \
  CONFIGURATION_BUILD_DIR="$PWD/.local/ios-build" \
  OBJROOT="$PWD/.local/ios-obj" SYMROOT="$PWD/.local/ios-sym" build
