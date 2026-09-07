#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local
xcrun swiftc apps/ios/DroneMatch/Models.swift apps/ios/DroneMatch/CommunityModels.swift scripts/ios-model-check.swift -o .local/ios-model-check
.local/ios-model-check
