import Foundation

@main enum RemoteLocationCheck {
    @MainActor static func main() throws {
        let suite = "RemoteLocationCheck-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RemoteLocationStore(defaults: defaults)
        assert(store.locations.isEmpty && store.error == nil)
        let location = RemoteLocation(name: "Lab", hostAlias: "sam@lab", directory: "/srv/Work ' 空間", tmuxExecutable: "/opt/homebrew/bin/tmux")
        try store.save(location)
        let data = defaults.data(forKey: RemoteLocationStore.defaultsKey)!
        let restored = RemoteLocationStore(defaults: defaults)
        assert(restored.locations == [location] && restored.error == nil)
        let ordinary = try location.profile(persistent: false)
        assert(ordinary.mode == .shell && ordinary.sessionName.isEmpty && ordinary.tmuxExecutable == nil)
        let first = try location.profile(persistent: true), second = try location.profile(persistent: true)
        assert(first.isPersistent && first.sessionName != second.sessionName && first.tmuxExecutable == location.tmuxExecutable)
        let serverDefault = RemoteLocation(name: "Login", hostAlias: "lab")
        _ = try serverDefault.profile(persistent: false)
        expectFailure { try serverDefault.profile(persistent: true) }
        var bad = location
        bad.hostAlias = "-oProxyCommand=unsafe"
        expectFailure { try store.save(bad) }
        assert(store.locations == [location] && defaults.data(forKey: RemoteLocationStore.defaultsKey) == data)
        var renamed = location
        renamed.name = "Build Lab"
        try store.save(renamed)
        assert(store.locations == [renamed])
        try store.remove(location.id)
        assert(store.locations.isEmpty)

        for corrupt: Any in ["wrong storage type", Data("not json".utf8), Data(repeating: 0, count: 256 * 1_024 + 1)] {
            defaults.set(corrupt, forKey: RemoteLocationStore.defaultsKey)
            let failed = RemoteLocationStore(defaults: defaults)
            assert(failed.locations.isEmpty && failed.error != nil)
            expectFailure { try failed.save(location) }
            assert(NSDictionary(dictionary: ["value": defaults.object(forKey: RemoteLocationStore.defaultsKey)!])
                .isEqual(to: ["value": corrupt]), "Invalid stored locations must remain unchanged")
        }
        let encoder = JSONEncoder()
        struct InvalidArchive: Encodable { let version: Int; let locations: [RemoteLocation] }
        for archive in [InvalidArchive(version: 2, locations: []), InvalidArchive(version: 1, locations: [location, location])] {
            defaults.set(try encoder.encode(archive), forKey: RemoteLocationStore.defaultsKey)
            assert(RemoteLocationStore(defaults: defaults).error != nil)
        }
        print("PASS SSH favorite persistence, exact locations, distinct shell/tmux modes, fresh tmux identities and failed-save preservation")
    }

    private static func expectFailure(_ operation: () throws -> Any) {
        do { _ = try operation(); preconditionFailure("Expected rejection") } catch {}
    }
}
