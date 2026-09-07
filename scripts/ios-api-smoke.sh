#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .local
xcrun swiftc apps/ios/DroneMatch/APIClient.swift apps/ios/DroneMatch/Models.swift apps/ios/DroneMatch/CommunityModels.swift scripts/ios-api-smoke.swift -o .local/ios-api-smoke
.local/ios-api-smoke
