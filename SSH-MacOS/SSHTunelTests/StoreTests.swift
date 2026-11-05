import Foundation
import Testing
@testable import SSHTunel

@MainActor
struct StoreTests {
    private let dir = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString)")
    private var url: URL { dir.appendingPathComponent("configs.json") }

    private func makeStore() -> SSHConfigStore { SSHConfigStore(saveURL: url, observeSystem: false) }

    @Test func addNamesAndPortsAreUnique() {
        let store = makeStore()
        store.addConfiguration()
        store.addConfiguration()
        #expect(store.configurations.map(\.name) == [SSHConfigStore.defaultName(1), SSHConfigStore.defaultName(2)])
        #expect(store.configurations.flatMap { $0.connection.forwardRules.map(\.localPort) } == ["5901", "5902"])
        #expect(store.selectedID == store.configurations.last?.id)

        store.configurations[0].name = SSHConfigStore.defaultName(3)
        store.addConfiguration()
        #expect(store.configurations.last?.name == SSHConfigStore.defaultName(4))
    }

    @Test func duplicateCopiesSettingsWithFreshIDsAndFreePorts() throws {
        let store = makeStore()
        store.addConfiguration()
        store.addConfiguration()
        let original = store.configurations[0]
        original.name = "Palau"
        original.connection.host = "bsd"
        original.connection.user = "albert"
        original.connection.keyPath = ""
        original.connection.addForwardRule()
        let originalPorts = original.connection.forwardRules.map(\.localPort)

        let copy = try #require(store.duplicate(id: original.id))
        #expect(store.configurations.map(\.id) == [original.id, copy.id, store.configurations[2].id])
        #expect(store.selectedID == copy.id)
        #expect(copy.name == SSHConfigStore.copyName(of: "Palau", existing: []))
        #expect(copy.connection.host == "bsd")
        #expect(copy.connection.user == "albert")
        #expect(copy.connection.keyPath == "")
        #expect(copy.connection.forwardRules.map(\.name) == original.connection.forwardRules.map(\.name))
        #expect(Set(copy.connection.forwardRules.map(\.id)).isDisjoint(with: original.connection.forwardRules.map(\.id)))

        // No local port is shared with any other configuration.
        let others = store.configurations.filter { $0.id != copy.id }
            .flatMap { $0.connection.forwardRules.map(\.localPort) }
        #expect(Set(copy.connection.forwardRules.map(\.localPort)).isDisjoint(with: others))
        #expect(original.connection.forwardRules.map(\.localPort) == originalPorts)
        #expect(copy.connection.validationError() == nil)

        let second = try #require(store.duplicate(id: original.id))
        #expect(second.name != copy.name)
        #expect(store.duplicate(id: UUID()) == nil)
    }

    @Test func copyNamesAreUnique() {
        let first = SSHConfigStore.copyName(of: "A", existing: [])
        let second = SSHConfigStore.copyName(of: "A", existing: ["A", first])
        #expect(first != second)
        #expect(first.contains("A") && second.contains("2"))
    }

    @Test func saveReloadMoveAndRemove() throws {
        let store = makeStore()
        for _ in 0..<3 { store.addConfiguration() }
        store.configurations[0].name = "A"
        store.configurations[1].name = "B"
        store.configurations[2].name = "C"
        store.move(from: IndexSet(integer: 2), to: 0)
        store.saveNow()

        let reloaded = makeStore()
        #expect(reloaded.configurations.map(\.name) == ["C", "A", "B"])
        #expect(reloaded.configurations.map(\.id) == store.configurations.map(\.id))

        reloaded.selectedID = reloaded.configurations[1].id
        reloaded.remove(id: reloaded.configurations[1].id)
        #expect(reloaded.configurations.map(\.name) == ["C", "B"])
        #expect(reloaded.selectedConfiguration?.name == "B", "Selection moves to the neighbour")

        reloaded.remove(id: reloaded.configurations[0].id)
        #expect(reloaded.selectedConfiguration?.name == "B", "Removing another row keeps the selection")
        try? FileManager.default.removeItem(at: dir)
    }

    @Test func unreadableFileIsBackedUpBeforeOverwrite() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("not json".utf8).write(to: url)

        let store = makeStore()
        #expect(store.configurations.isEmpty)
        store.addConfiguration()
        store.saveNow()

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let backup = try #require(files.first { $0.hasPrefix("configs.recovery-") })
        #expect(try String(contentsOf: dir.appendingPathComponent(backup), encoding: .utf8) == "not json")
        #expect(makeStore().configurations.count == 1)
    }

    @Test func decodesOldFilesWithoutIDs() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let json = """
        [{"connection":{"host":"h","user":"u","sshPort":"","keyPath":"","autoReconnect":false,
          "forwardRules":[{"localPort":"1","remoteHost":"x","remotePort":"2"}]}}]
        """
        try Data(json.utf8).write(to: url)

        let store = makeStore()
        let cfg = try #require(store.configurations.first)
        #expect(cfg.name == String(localized: "Connection"))
        #expect(cfg.connection.forwardRules.first?.name == "")
        #expect(cfg.connection.host == "h")
    }
}
