import Combine
import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var isConfigured = false
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?
    @Published private(set) var statusMessage = "Updates are not configured for this build."
    private var controller: SPUStandardUpdaterController?
    private var didStart = false

    func start() {
        guard !didStart else { return }
        didStart = true
        do {
            guard try UpdateConfiguration.read(Bundle.main.infoDictionary ?? [:]) != nil else { return }
            let controller = SPUStandardUpdaterController(startingUpdater: false,
                updaterDelegate: self, userDriverDelegate: nil)
            try controller.updater.start()
            self.controller = controller
            isConfigured = true
            statusMessage = "Updates install only when you choose. Trellis checks active work before quitting."
            controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
            controller.updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastUpdateCheckDate)
        } catch {
            statusMessage = "Updates are unavailable: \(error.localizedDescription)"
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        controller?.updater.checkForUpdates()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        // Sparkle owns this preference. Only an explicit user change writes it.
        controller?.updater.automaticallyChecksForUpdates = enabled
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let failure = error as NSError
        if failure.domain == SUSparkleErrorDomain {
            if failure.code == SUError.noUpdateError.rawValue { statusMessage = "You’re up to date."; return }
            if failure.code == SUError.installationCanceledError.rawValue { statusMessage = "Update installation was cancelled."; return }
        }
        statusMessage = "The update could not finish: \(error.localizedDescription)"
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        statusMessage = "Trellis \(item.displayVersionString) is available."
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        statusMessage = "You’re up to date."
    }
}
