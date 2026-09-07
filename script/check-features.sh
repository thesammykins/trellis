#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/.build-support/check-features"
mkdir -p "$BUILD"
cd "$ROOT"

run() {
  local name="$1"
  shift
  # The existing async fixtures predate Swift 6 region-isolation annotations.
  xcrun swiftc -swift-version 5 Trellis/AppStorageLocation.swift "$@" -o "$BUILD/$name"
  "$BUILD/$name"
}

run workspace-archive Trellis/ShellConfiguration.swift Trellis/MultiplexerProfile.swift Trellis/CustomHarness.swift Trellis/PaneLayout.swift Trellis/LaunchProfile.swift Trellis/AgentResume.swift Trellis/WorkspaceArchive.swift Trellis/RemoteProfile.swift Checks/WorkspaceArchiveCheck.swift
run memory-store Trellis/MemoryStore.swift Checks/MemoryStoreCheck.swift
run remote-profile Trellis/RemoteProfile.swift Checks/RemoteProfileCheck.swift
run direct-model Trellis/DirectModelClient.swift Checks/DirectModelCheck.swift
run codex-model Trellis/CodexModelClient.swift Checks/CodexModelCheck.swift
run dreaming-run Trellis/MemoryStore.swift Trellis/DirectModelClient.swift Trellis/DreamingRun.swift Checks/DreamingRunCheck.swift
run dreaming-schedule -framework SwiftUI -framework Security \
  Trellis/LaunchProfile.swift Trellis/MemoryStore.swift Trellis/MemoryIntegration.swift Trellis/DirectModelClient.swift \
  Trellis/TerminalPreferences.swift Trellis/TerminalPreferencesView.swift Trellis/ShellConfiguration.swift Trellis/ShellConfigurationView.swift Trellis/AgentInstallation.swift Trellis/AccountSetup.swift Trellis/DreamingRun.swift Trellis/AppTheme.swift Trellis/ThemeBrowser.swift Trellis/ThemeState.swift Trellis/GhosttyImport.swift Trellis/GhosttyImportView.swift Trellis/DirectModelCatalog.swift Trellis/GoogleFonts.swift Trellis/AppSettings.swift Trellis/DreamingScheduler.swift \
  Checks/DreamingScheduleCheck.swift

run agent-resume Trellis/LaunchProfile.swift Trellis/AgentResume.swift Checks/AgentResumeCheck.swift

run account-setup -framework SwiftUI -framework AppKit -framework Security Trellis/LaunchProfile.swift Trellis/ShellConfiguration.swift Trellis/ShellConfigurationView.swift Trellis/TerminalPreferences.swift Trellis/TerminalPreferencesView.swift Trellis/AgentInstallation.swift Trellis/AccountSetup.swift Trellis/AppTheme.swift Trellis/ThemeBrowser.swift Trellis/ThemeState.swift Trellis/GhosttyImport.swift Trellis/GhosttyImportView.swift Trellis/DirectModelCatalog.swift Trellis/GoogleFonts.swift Trellis/DirectModelClient.swift Trellis/AppSettings.swift Checks/AccountSetupCheck.swift

run agent-model-catalog Trellis/LaunchProfile.swift Trellis/AgentInstallation.swift Trellis/AgentModelCatalog.swift Checks/AgentModelCatalogCheck.swift

run pane-layout Trellis/ShellConfiguration.swift Trellis/MultiplexerProfile.swift Trellis/CustomHarness.swift Trellis/PaneLayout.swift Trellis/LaunchProfile.swift Trellis/AgentResume.swift Trellis/WorkspaceArchive.swift Trellis/RemoteProfile.swift Checks/PaneLayoutCheck.swift

run custom-harness Trellis/CustomHarness.swift Checks/CustomHarnessCheck.swift
run terminal-preferences -framework AppKit Trellis/TerminalPreferences.swift Checks/TerminalPreferencesCheck.swift
run shell-configuration Trellis/ShellConfiguration.swift Checks/ShellConfigurationCheck.swift

run multiplexer Trellis/MultiplexerProfile.swift Checks/MultiplexerProfileCheck.swift

run native-agent Trellis/ReusableAgentTools.swift Trellis/MemoryStore.swift Trellis/AgentInstructions.swift Trellis/DirectModelClient.swift Trellis/NativeAgentTools.swift Trellis/NativeAgentRuntime.swift Checks/NativeAgentCheck.swift

run git-snapshot Trellis/GitSnapshot.swift Checks/GitSnapshotCheck.swift

run shell-integration Trellis/ShellIntegration.swift Checks/ShellIntegrationCheck.swift

run app-theme Trellis/AppTheme.swift Checks/AppThemeCheck.swift
run agent-instructions Trellis/AgentInstructions.swift Checks/AgentInstructionsCheck.swift
run persistent-sessions Trellis/PersistentSessions.swift Trellis/RemoteProfile.swift Trellis/MultiplexerProfile.swift Trellis/AgentInstallation.swift Trellis/LaunchProfile.swift Checks/PersistentSessionsCheck.swift

run ghostty-import -framework AppKit Trellis/TerminalPreferences.swift Trellis/AppTheme.swift Trellis/GhosttyImport.swift Checks/GhosttyImportCheck.swift

run session-organization Trellis/SessionOrganization.swift Checks/SessionOrganizationCheck.swift
run workspace-appearance Trellis/WorkspaceAppearance.swift Checks/WorkspaceAppearanceCheck.swift
run session-identity -framework AppKit -framework ImageIO -framework UniformTypeIdentifiers Trellis/SessionIdentity.swift Checks/SessionIdentityCheck.swift

run terminal-location Trellis/TerminalLocation.swift Checks/TerminalLocationCheck.swift
run files -framework SwiftUI -framework AppKit Trellis/FilesPanel.swift Checks/FilesCheck.swift

run google-fonts -framework AppKit -framework CoreText Trellis/GoogleFonts.swift Checks/GoogleFontsCheck.swift

run direct-model-catalog -framework SwiftUI Trellis/DirectModelCatalog.swift Checks/DirectModelCatalogCheck.swift
