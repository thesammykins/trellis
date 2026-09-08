import Foundation

@main enum ModelConnectionsCheck {
    @MainActor static func main() throws {
        let suite = "Trellis-model-connections-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModelConnectionStore(defaults: defaults)
        let connection = ModelConnection(name: "Fixture", endpoint: "https://fixture.invalid/v1", api: .responses)
        try store.save(connection)
        assert(ModelConnectionStore(defaults: defaults).connections == [connection])
        var invalid = connection
        invalid.endpoint = "https://user:secret@fixture.invalid/v1"
        do { try store.save(invalid); assertionFailure("Credential URLs must fail") } catch {}
        assert(store.connections == [connection])
        try store.remove(connection.id)
        assert(ModelConnectionStore(defaults: defaults).connections.isEmpty)
        defaults.set(Data("not json".utf8), forKey: "modelConnections.v1")
        let corrupt = ModelConnectionStore(defaults: defaults)
        do { try corrupt.save(connection); assertionFailure("Do not overwrite corrupt data") } catch {}
        assert(defaults.data(forKey: "modelConnections.v1") == Data("not json".utf8))

        let first = ["direct", "https://one.invalid/v1"]
        let second = ["direct", "https://two.invalid/v1"]
        ModelCatalogCache.save(["advertised-model"], scope: first, defaults: defaults)
        assert(ModelCatalogCache.load(String.self, scope: first, defaults: defaults)?.models == ["advertised-model"])
        assert(ModelCatalogCache.load(String.self, scope: second, defaults: defaults) == nil)
        ModelCatalogCache.remove(scope: first, defaults: defaults)
        assert(ModelCatalogCache.load(String.self, scope: first, defaults: defaults) == nil)
        for index in 0..<30 { ModelCatalogCache.save(["model"], scope: ["fixture", "\(index)"], defaults: defaults) }
        assert(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("modelCatalog.v1.") }.count == 16)
        print("PASS saved connections: scoped persistence, invalid/corrupt preservation; model cache isolation and bounded retention")
    }
}
