import CryptoKit
import Foundation

/// Discovery is a dated hint, never an entitlement check. Credentials are not cached here.
enum ModelCatalogCache {
    struct Snapshot<Model: Codable>: Codable {
        let models: [Model]
        let fetchedAt: Date
    }

    static func load<Model: Codable>(_ type: Model.Type, scope: [String], defaults: UserDefaults = .standard) -> Snapshot<Model>? {
        guard let data = defaults.data(forKey: key(scope)), data.count <= 512 * 1_024,
              let snapshot = try? JSONDecoder().decode(Snapshot<Model>.self, from: data),
              snapshot.models.count <= 2_000, snapshot.fetchedAt.timeIntervalSince1970.isFinite,
              snapshot.fetchedAt <= Date().addingTimeInterval(300) else { return nil }
        return snapshot
    }

    static func save<Model: Codable>(_ models: [Model], scope: [String], defaults: UserDefaults = .standard) {
        guard models.count <= 2_000,
              let data = try? JSONEncoder().encode(Snapshot(models: models, fetchedAt: Date())),
              data.count <= 512 * 1_024 else { return }
        let cacheKey = key(scope)
        // Bound account/project catalogue accumulation without touching other preferences.
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("modelCatalog.v1.") && $0 != cacheKey }
        for old in keys.sorted().prefix(max(0, keys.count - 15)) { defaults.removeObject(forKey: old) }
        defaults.set(data, forKey: cacheKey)
    }

    static func remove(scope: [String], defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(scope))
    }

    private static func key(_ scope: [String]) -> String {
        let data = (try? JSONEncoder().encode(scope)) ?? Data()
        return "modelCatalog.v1." + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
