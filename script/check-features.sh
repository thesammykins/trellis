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
run agent-team Trellis/DirectModelClient.swift Trellis/AgentTeam.swift Checks/AgentTeamCheck.swift
run agent-context-budget Trellis/DirectModelClient.swift Trellis/AgentContextBudget.swift Checks/AgentContextBudgetCheck.swift
run codex-model Trellis/CodexModelClient.swift Checks/CodexModelCheck.swift
run dreaming-run Trellis/MemoryStore.swift Trellis/DirectModelClient.swift Trellis/DreamingRun.swift Checks/DreamingRunCheck.swift
run dreaming-schedule -framework SwiftUI -framework Security \
  Trellis/LaunchProfile.swift Trellis/MemoryStore.swift Trellis/MemoryIntegration.swift Trellis/DirectModelClient.swift \
  Trellis/AgentInstallation.swift Trellis/EndpointKey.swift Trellis/DreamingRun.swift Trellis/DreamingScheduler.swift \
  Checks/DreamingScheduleCheck.swift

run agent-resume Trellis/LaunchProfile.swift Trellis/AgentResume.swift Checks/AgentResumeCheck.swift

run account-setup -framework Security Trellis/LaunchProfile.swift Trellis/AgentInstallation.swift Trellis/AccountSetup.swift Trellis/EndpointKey.swift Trellis/SettingsPage.swift Checks/AccountSetupCheck.swift

run agent-model-catalog -framework SwiftUI Trellis/ModelCatalogCache.swift Trellis/AgentModelPicker.swift Trellis/LaunchProfile.swift Trellis/AgentInstallation.swift Trellis/AgentModelCatalog.swift Checks/AgentModelCatalogCheck.swift

run pane-layout Trellis/ShellConfiguration.swift Trellis/MultiplexerProfile.swift Trellis/CustomHarness.swift Trellis/PaneLayout.swift Trellis/LaunchProfile.swift Trellis/AgentResume.swift Trellis/WorkspaceArchive.swift Trellis/RemoteProfile.swift Checks/PaneLayoutCheck.swift

run custom-harness Trellis/CustomHarness.swift Checks/CustomHarnessCheck.swift
run terminal-preferences -framework AppKit Trellis/TerminalPreferences.swift Checks/TerminalPreferencesCheck.swift
run shell-configuration Trellis/ShellConfiguration.swift Checks/ShellConfigurationCheck.swift

run multiplexer Trellis/MultiplexerProfile.swift Checks/MultiplexerProfileCheck.swift

run native-agent Trellis/ReusableAgentTools.swift Trellis/MemoryStore.swift Trellis/AgentInstructions.swift Trellis/DirectModelClient.swift Trellis/AgentTeam.swift Trellis/NativeAgentTools.swift Trellis/AgentContextBudget.swift Trellis/AgentDelegation.swift Trellis/NativeAgentRuntime.swift Checks/NativeAgentCheck.swift
run automation-schedule Trellis/ReusableAgentTools.swift Trellis/MemoryStore.swift Trellis/AgentInstructions.swift Trellis/DirectModelClient.swift Trellis/AgentTeam.swift Trellis/NativeAgentTools.swift Trellis/AutomationScheduler.swift Checks/AutomationScheduleCheck.swift

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

run direct-model-catalog -framework SwiftUI Trellis/ModelCatalogCache.swift Trellis/DirectModelCatalog.swift Checks/DirectModelCatalogCheck.swift

run markdown-fences Trellis/MarkdownFenceParser.swift Checks/MarkdownFenceParserCheck.swift

run project-directory Trellis/ProjectDirectory.swift Checks/ProjectDirectoryCheck.swift
run harness-discovery Trellis/CustomHarness.swift Trellis/HarnessDiscovery.swift Checks/HarnessDiscoveryCheck.swift

run model-connections Trellis/DirectModelClient.swift Trellis/ModelConnections.swift Trellis/ModelCatalogCache.swift Checks/ModelConnectionsCheck.swift
run update-configuration Trellis/UpdateConfiguration.swift Checks/UpdateConfigurationCheck.swift

run remote-location Trellis/RemoteProfile.swift Trellis/RemoteLocationStore.swift Checks/RemoteLocationCheck.swift
run native-pane-split -framework AppKit -framework SwiftUI Trellis/NativePaneSplitView.swift Checks/NativePaneSplitCheck.swift
run codex-subscription Trellis/LaunchProfile.swift Trellis/AgentInstallation.swift Trellis/AgentModelCatalog.swift Trellis/ReusableAgentTools.swift Trellis/MemoryStore.swift Trellis/AgentInstructions.swift Trellis/DirectModelClient.swift Trellis/AgentTeam.swift Trellis/NativeAgentTools.swift Trellis/AgentContextBudget.swift Trellis/AgentDelegation.swift Trellis/NativeAgentRuntime.swift Trellis/CodexSubscriptionClient.swift Trellis/CodexConversationRuntime.swift Checks/CodexSubscriptionCheck.swift
run closing-workspace-cleanup Trellis/ClosingWorkspaceCleanup.swift Checks/ClosingWorkspaceCleanupCheck.swift
