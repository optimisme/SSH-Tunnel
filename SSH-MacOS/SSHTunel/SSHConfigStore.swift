//  SSHConfigStore.swift

import SwiftUI
import Foundation
import Combine
import AppKit

private func decodedUUID<K: CodingKey>(from container: KeyedDecodingContainer<K>, forKey key: K) throws -> UUID {
    if let raw = try container.decodeIfPresent(String.self, forKey: key),
       let uuid = UUID(uuidString: raw) {
        return uuid
    }
    return UUID()
}

struct PortForwardRule: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var localPort: String
    var remoteHost: String
    var remotePort: String

    enum CodingKeys: String, CodingKey {
        case id, name, localPort, remoteHost, remotePort
    }

    init(id: UUID = UUID(), name: String, localPort: String, remoteHost: String, remotePort: String) {
        self.id = id
        self.name = name
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try decodedUUID(from: container, forKey: .id)
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.localPort = try container.decode(String.self, forKey: .localPort)
        self.remoteHost = try container.decode(String.self, forKey: .remoteHost)
        self.remotePort = try container.decode(String.self, forKey: .remotePort)
    }
}

@MainActor
final class SSHConfiguration: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    let connection: SSHConnectionController

    struct Snapshot: Codable {
        var id: UUID
        var name: String
        var connection: SSHConnectionController.Snapshot

        enum CodingKeys: String, CodingKey {
            case id, name, connection
        }

        init(id: UUID, name: String, connection: SSHConnectionController.Snapshot) {
            self.id = id
            self.name = name
            self.connection = connection
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try decodedUUID(from: container, forKey: .id)
            self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? String(localized: "Connection", comment: "Fallback configuration name")
            self.connection = try container.decodeIfPresent(SSHConnectionController.Snapshot.self, forKey: .connection)
                ?? SSHConnectionController.Snapshot(
                    host: "",
                    user: "",
                    sshPort: "",
                    keyPath: SSHConnectionController.defaultKeyPath,
                    forwardRules: [
                        PortForwardRule(name: SSHConnectionController.ruleName(1), localPort: "5901", remoteHost: "localhost", remotePort: "5900")
                    ],
                    autoReconnect: false
                )
        }
    }

    init(name: String, defaultLocalPort: String) {
        self.id = UUID()
        self.name = name
        self.connection = SSHConnectionController(defaultLocalPort: defaultLocalPort)
    }

    init(snapshot: Snapshot) {
        self.id = snapshot.id
        self.name = snapshot.name
        self.connection = SSHConnectionController(snapshot: snapshot.connection)
    }

    func snapshot() -> Snapshot {
        Snapshot(id: id, name: name, connection: connection.snapshot())
    }
}

@MainActor
final class SSHConfigStore: ObservableObject {
    @Published var configurations: [SSHConfiguration]
    @Published var selectedID: UUID?

    private var cancellables: Set<AnyCancellable> = []
    private var configCancellables: [AnyCancellable] = []
    private var saveWorkItem: DispatchWorkItem?
    private let saveURL: URL
    private var needsUnreadableBackup = false
    private var lastSavedData: Data?

    nonisolated static var defaultSaveURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support
            .appendingPathComponent("SSH-TunelApp", isDirectory: true)
            .appendingPathComponent("configs.json")
    }

    /// - Parameters:
    ///   - saveURL: where configurations are stored (tests pass a temporary file).
    ///   - observeSystem: follow sleep/wake/quit notifications and probe tunnels on launch.
    init(saveURL: URL = SSHConfigStore.defaultSaveURL, observeSystem: Bool = true) {
        try? FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        self.saveURL = saveURL

        switch Self.loadConfigs(from: saveURL) {
        case .loaded(let loaded, let data):
            configurations = loaded
            lastSavedData = data
        case .missing:
            configurations = []
        case .unreadable:
            configurations = []
            needsUnreadableBackup = true
        }
        selectedID = configurations.first?.id

        attachObservers()

        $configurations
            .dropFirst()
            .sink { [weak self] _ in
                // Runs in willSet; defer so observers see the new array.
                DispatchQueue.main.async {
                    self?.attachObservers()
                    self?.scheduleSave()
                }
            }
            .store(in: &cancellables)

        guard observeSystem else { return }

        let ws = NSWorkspace.shared.notificationCenter
        ws.publisher(for: NSWorkspace.willSleepNotification)
            .sink { [weak self] _ in self?.configurations.forEach { $0.connection.systemWillSleep() } }
            .store(in: &cancellables)
        ws.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in self?.configurations.forEach { $0.connection.systemDidWake() } }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.saveNow() }
            .store(in: &cancellables)

        // Show the real state of every tunnel (they survive app restarts via ControlPersist).
        configurations.forEach { $0.connection.refresh() }
    }

    var selectedConfiguration: SSHConfiguration? {
        guard let id = selectedID else { return nil }
        return configurations.first { $0.id == id }
    }

    var runningConfigurations: [SSHConfiguration] {
        configurations.filter { $0.connection.isRunning }
    }

    static func defaultName(_ index: Int) -> String {
        String(localized: "Connection \(index)", comment: "Default name of a new SSH configuration")
    }

    func addConfiguration() {
        let names = Set(configurations.map(\.name))
        var idx = configurations.count + 1
        while names.contains(Self.defaultName(idx)) { idx += 1 }

        let usedPorts = Set(configurations.flatMap { $0.connection.forwardRules.compactMap { Int($0.localPort) } })
        var port = 5901
        while usedPorts.contains(port) { port += 1 }

        let cfg = SSHConfiguration(name: Self.defaultName(idx), defaultLocalPort: "\(port)")
        configurations.append(cfg)
        selectedID = cfg.id
    }

    func move(from source: IndexSet, to destination: Int) {
        configurations.move(fromOffsets: source, toOffset: destination)
    }

    func remove(id: UUID) {
        guard let idx = configurations.firstIndex(where: { $0.id == id }) else { return }

        configurations[idx].connection.stop()
        configurations.remove(at: idx)
        if selectedID == id || selectedID == nil {
            selectedID = configurations.isEmpty ? nil : configurations[min(idx, configurations.count - 1)].id
        }
    }

    /// Stops every running tunnel and waits for them (used on quit).
    func stopAll() async {
        await withTaskGroup(of: Void.self) { group in
            for cfg in runningConfigurations {
                group.addTask { await cfg.connection.stopAndWait() }
            }
        }
    }

    /// Writes pending changes now (normally saves are debounced).
    func saveNow() {
        saveWorkItem?.cancel()
        save()
    }

    private func attachObservers() {
        configCancellables = configurations.flatMap { cfg in
            [
                cfg.objectWillChange.sink { [weak self] _ in self?.scheduleSave() },
                cfg.connection.objectWillChange.sink { [weak self] _ in self?.scheduleSave() }
            ]
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func save() {
        guard prepareUnreadableBackupIfNeeded() else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(configurations.map { $0.snapshot() })
            // Status/log changes also trigger saves; skip the write if nothing persisted changed.
            guard data != lastSavedData else { return }
            try data.write(to: saveURL, options: .atomic)
            lastSavedData = data
        } catch {
            NSLog("SSHTunel: failed to save configurations: \(error)")
        }
    }

    private func prepareUnreadableBackupIfNeeded() -> Bool {
        guard needsUnreadableBackup else { return true }
        guard FileManager.default.fileExists(atPath: saveURL.path) else {
            needsUnreadableBackup = false
            return true
        }

        do {
            try FileManager.default.copyItem(at: saveURL, to: Self.makeRecoveryBackupURL(for: saveURL))
            needsUnreadableBackup = false
            return true
        } catch {
            return false
        }
    }

    private static func loadConfigs(from url: URL) -> LoadResult {
        guard let data = try? Data(contentsOf: url) else { return .missing }
        do {
            let snaps = try JSONDecoder().decode([SSHConfiguration.Snapshot].self, from: data)
            return .loaded(snaps.map { SSHConfiguration(snapshot: $0) }, data)
        } catch {
            return .unreadable
        }
    }

    private enum LoadResult {
        case missing
        case loaded([SSHConfiguration], Data)
        case unreadable
    }

    private static func makeRecoveryBackupURL(for url: URL) -> URL {
        let baseName = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let suffix = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.lowercased())"
        let fileName = ext.isEmpty
            ? "\(baseName).recovery-\(suffix)"
            : "\(baseName).recovery-\(suffix).\(ext)"
        return url.deletingLastPathComponent().appendingPathComponent(fileName)
    }
}
