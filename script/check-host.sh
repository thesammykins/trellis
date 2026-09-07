#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build-support
xcrun swiftc -swift-version 6 Trellis/SecureInputController.swift Checks/SecureInputCheck.swift -o .build-support/check-secure-input
.build-support/check-secure-input
xcrun swiftc -swift-version 6 -I .build-support/ghostty/include \
  -L .build-support/ghostty/macos/GhosttyKit.xcframework/macos-arm64 \
  Trellis/TerminalView.swift Trellis/AgentInstallation.swift Trellis/LaunchProfile.swift Checks/DragPathCheck.swift \
  -lghostty-fat -lc++ -framework Cocoa -framework Metal -framework QuartzCore \
  -framework Carbon -framework CoreVideo -framework IOKit -o .build-support/check-drag-paths
.build-support/check-drag-paths
xcrun swiftc -swift-version 6 Trellis/LaunchProfile.swift Checks/LaunchProfileCheck.swift -o .build-support/check-launch-profiles
.build-support/check-launch-profiles
xcrun swiftc -swift-version 6 Trellis/LaunchProfile.swift Trellis/AgentInstallation.swift Checks/AgentInstallationCheck.swift -o .build-support/check-agent-installation
.build-support/check-agent-installation
