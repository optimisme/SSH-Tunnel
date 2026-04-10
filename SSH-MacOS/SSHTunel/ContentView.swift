//  ContentView.swift

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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(localPort, forKey: .localPort)
        try container.encode(remoteHost, forKey: .remoteHost)
        try container.encode(remotePort, forKey: .remotePort)
    }
}

@MainActor
final class SSHConnectionController: ObservableObject, Identifiable {
    let id = UUID()
    struct Snapshot: Codable {
        var host: String
        var user: String
        var sshPort: String
        var keyPath: String
        var forwardRules: [PortForwardRule]
        var autoReconnect: Bool
    }
    @Published var status = "Aturat"
    @Published var isRunning = false

    @Published var host = ""
    @Published var user = ""
    @Published var sshPort = ""
    @Published var keyPath = ""
    @Published var forwardRules: [PortForwardRule]

    @Published var autoReconnect = false
    @Published var logText = ""

    private var process: Process?
    private var timer: Timer?
    private var reconnectTask: Task<Void, Never>?
    private var failures = 0
    private var stopRequested = false
    private var attemptedSMBMountLocalPorts: Set<String> = []
    private var attemptedSMBMountRuleIDs: Set<UUID> = []

    private var didAttemptKnownHostsFix = false

    private let sshPath = "/usr/bin/ssh"
    private let lsofPath = "/usr/sbin/lsof"
    private let keyscanPath = "/usr/bin/ssh-keyscan"
    private let psPath = "/bin/ps"
    private let killPath = "/bin/kill"
    private let umountPath = "/sbin/umount"
    private let diskutilPath = "/usr/sbin/diskutil"

    private var externalMatchingPid: Int32?

    init(defaultLocalPort: String) {
        self.forwardRules = [PortForwardRule(name: "Regla 1", localPort: defaultLocalPort, remoteHost: "localhost", remotePort: "5900")]
    }

    init(snapshot: Snapshot) {
        self.host = snapshot.host
        self.user = snapshot.user
        self.sshPort = snapshot.sshPort
        self.keyPath = snapshot.keyPath
        self.forwardRules = snapshot.forwardRules
        self.autoReconnect = snapshot.autoReconnect
    }

    func snapshot() -> Snapshot {
        Snapshot(host: host,
                 user: user,
                 sshPort: sshPort,
                 keyPath: keyPath,
                 forwardRules: forwardRules,
                 autoReconnect: autoReconnect)
    }

    func start() {
        stopRequested = false
        failures = 0
        didAttemptKnownHostsFix = false
        externalMatchingPid = nil
        attemptedSMBMountLocalPorts.removeAll()
        attemptedSMBMountRuleIDs.removeAll()
        logText = ""
        status = "Connectant…"
        startInternal()
    }

    func stop() {
        stopRequested = true
        reconnectTask?.cancel()
        reconnectTask = nil

        unmountSMBForForwardRules()

        if sshControlExit() {
            process?.terminate()
            process = nil
            externalMatchingPid = nil
            stopTimer()
            isRunning = false
            status = "Aturat"
            return
        }

        if let pid = externalMatchingPid {
            _ = killPid(pid)
            externalMatchingPid = nil
        }

        process?.terminate()
        process = nil

        stopTimer()
        isRunning = false
        status = "Aturat"
        attemptedSMBMountLocalPorts.removeAll()
        attemptedSMBMountRuleIDs.removeAll()
    }

    func clearLog() {
        logText = ""
    }

    func addForwardRule() {
        guard !isRunning else { return }
        forwardRules.append(
            PortForwardRule(
                name: suggestedRuleName(),
                localPort: suggestedLocalPort(),
                remoteHost: "localhost",
                remotePort: "5900"
            )
        )
    }

    func removeForwardRule(id: UUID) {
        guard !isRunning else { return }
        guard forwardRules.count > 1 else { return }
        forwardRules.removeAll { $0.id == id }
    }

    private func suggestedLocalPort() -> String {
        let base = 5901
        let used = Set(forwardRules.compactMap { Int($0.localPort) })
        var port = base
        while used.contains(port) { port += 1 }
        return "\(port)"
    }

    private func suggestedRuleName() -> String {
        let base = "Regla"
        let used = Set(forwardRules.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) })
        var idx = 1
        while used.contains("\(base) \(idx)") { idx += 1 }
        return "\(base) \(idx)"
    }

    private func maybeMountSMBForForwardRules() {
        for rule in forwardRules {
            let remote = rule.remotePort.trimmingCharacters(in: .whitespacesAndNewlines)
            guard remote == "445" else { continue }
            guard !attemptedSMBMountRuleIDs.contains(rule.id) else { continue }
            attemptedSMBMountRuleIDs.insert(rule.id)

            let local = rule.localPort.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !local.isEmpty, UInt16(local) != nil else {
                appendLog("[error] Invalid local SMB forward port: \(rule.localPort)\n")
                continue
            }
            guard !attemptedSMBMountLocalPorts.contains(local) else { continue }
            attemptedSMBMountLocalPorts.insert(local)

            guard let url = smbHomeURL(localPort: local) else {
                appendLog("[error] Could not build SMB URL for user/home share on local port \(local)\n")
                continue
            }

            if NSWorkspace.shared.open(url) {
                appendLog("[info] Opening Finder SMB mount: \(url.absoluteString)\n")
            } else {
                appendLog("[error] Finder could not open SMB URL: \(url.absoluteString)\n")
            }
        }
    }

    private func smbHomeURL(localPort: String) -> URL? {
        let smbUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !smbUser.isEmpty else { return nil }
        guard let port = Int(localPort) else { return nil }

        let safePathChars = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        guard let encodedShare = smbUser.addingPercentEncoding(withAllowedCharacters: safePathChars) else { return nil }

        var components = URLComponents()
        components.scheme = "smb"
        components.host = "localhost"
        components.port = port
        components.user = smbUser
        components.percentEncodedPath = "/\(encodedShare)"
        return components.url
    }

    private struct SMBTarget: Hashable {
        let user: String
        let host: String
        let port: Int
        let path: String
    }

    private func unmountSMBForForwardRules() {
        let targets = smbTargetsForForwardRules()
        guard !targets.isEmpty else { return }

        guard let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeURLForRemountingKey],
            options: [.skipHiddenVolumes]
        ) else { return }

        for mountPoint in mounted {
            guard
                let values = try? mountPoint.resourceValues(forKeys: [.volumeURLForRemountingKey]),
                let remountURL = values.volumeURLForRemounting,
                isMatchingSMBRemountURL(remountURL, targets: targets)
            else { continue }

            if unmountVolume(at: mountPoint) {
                appendLog("[info] Unmounted SMB volume: \(mountPoint.path)\n")
            } else {
                appendLog("[error] Could not unmount SMB volume: \(mountPoint.path)\n")
            }
        }
    }

    private func smbTargetsForForwardRules() -> Set<SMBTarget> {
        var targets: Set<SMBTarget> = []
        for rule in forwardRules {
            let remote = rule.remotePort.trimmingCharacters(in: .whitespacesAndNewlines)
            guard remote == "445" else { continue }
            let local = rule.localPort.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = smbHomeURL(localPort: local), let target = smbTarget(from: url) else { continue }
            targets.insert(target)
        }
        return targets
    }

    private func smbTarget(from url: URL) -> SMBTarget? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard (c.scheme ?? "").lowercased() == "smb" else { return nil }
        guard let host = c.host?.lowercased(), !host.isEmpty else { return nil }
        guard let user = c.user, !user.isEmpty else { return nil }
        guard let port = c.port else { return nil }
        let path = c.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        return SMBTarget(user: user, host: host, port: port, path: path)
    }

    private func isMatchingSMBRemountURL(_ remountURL: URL, targets: Set<SMBTarget>) -> Bool {
        guard let c = URLComponents(url: remountURL, resolvingAgainstBaseURL: false) else { return false }
        guard (c.scheme ?? "").lowercased() == "smb" else { return false }
        guard let host = c.host?.lowercased(), !host.isEmpty else { return false }
        guard let user = c.user, !user.isEmpty else { return false }
        let path = c.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return false }

        for target in targets where target.host == host && target.user == user && target.path == path {
            if let p = c.port {
                if p == target.port { return true }
            } else if target.port == 445 {
                return true
            }
        }

        return false
    }

    private func unmountVolume(at mountPoint: URL) -> Bool {
        let first = runProcessSync(exe: umountPath, args: [mountPoint.path])
        if first.exitCode == 0 { return true }

        let second = runProcessSync(exe: diskutilPath, args: ["unmount", "force", mountPoint.path])
        return second.exitCode == 0
    }

    func checkInitialState() {
        let state = detectCurrentState()

        switch state {
        case .activeOursControlMaster:
            isRunning = true
            status = "Actiu (localhost:\(localPortsSummary))"
            maybeMountSMBForForwardRules()
            startTimer()

        case .activeMatchesConfigByPid(let pid):
            externalMatchingPid = pid
            isRunning = true
            status = "Actiu (localhost:\(localPortsSummary))"
            maybeMountSMBForForwardRules()
            startTimer()

        case .portUsedByOther:
            externalMatchingPid = nil
            isRunning = false
            status = "Error: port local ocupat (\(localPortsSummary))"
            stopTimer()

        case .stopped:
            externalMatchingPid = nil
            isRunning = false
            status = "Aturat"
            stopTimer()
        }
    }

    private var localPortsSummary: String {
        forwardRules.map { $0.localPort }.joined(separator: ",")
    }

    private func appendLog(_ s: String) {
        let t = s.trimmingCharacters(in: .newlines)
        guard !t.isEmpty else { return }
        if !logText.isEmpty { logText += "\n" }
        logText += t
    }

    private var controlSocketPath: String {
        let forwardRulesKey = forwardRules
            .map { "L\($0.localPort)->\($0.remoteHost):\($0.remotePort)" }
            .sorted()
            .joined(separator: "|")
        let base = "\(user)@\(host):\(sshPort)|\(forwardRulesKey)"
        let digest = stableShortHash(base)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ssh/tunnelctl_\(digest).sock"
    }

    private func stableShortHash(_ s: String) -> String {
        let data = Array(s.utf8)
        var hash: UInt64 = 14695981039346656037
        for b in data {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }

    private func sshTarget() -> String { "\(user)@\(host)" }

    private func isOurTunnelActive() -> Bool {
        let res = runProcessSync(exe: sshPath, args: [
            "-S", controlSocketPath,
            "-p", sshPort,
            "-O", "check",
            sshTarget()
        ])
        return res.exitCode == 0
    }

    private func sshControlExit() -> Bool {
        let res = runProcessSync(exe: sshPath, args: [
            "-S", controlSocketPath,
            "-p", sshPort,
            "-O", "exit",
            sshTarget()
        ])
        return res.exitCode == 0
    }

    private enum DetectedState {
        case activeOursControlMaster
        case activeMatchesConfigByPid(Int32)
        case portUsedByOther
        case stopped
    }

    private func detectCurrentState() -> DetectedState {
        if isOurTunnelActive() {
            return .activeOursControlMaster
        }

        for f in forwardRules {
            guard let lp = UInt16(f.localPort) else { continue }
            guard let pid = lsofListeningPid(port: lp) else { continue }

            let cmd = psCommandLine(pid: pid)
            if matchesOurTunnelCommandLine(cmd) {
                return .activeMatchesConfigByPid(pid)
            } else {
                return .portUsedByOther
            }
        }

        return .stopped
    }

    private func lsofListeningPid(port: UInt16) -> Int32? {
        let res = runProcessSync(exe: lsofPath, args: [
            "-nP",
            "-iTCP:\(port)",
            "-sTCP:LISTEN",
            "-Fp"
        ])
        if res.exitCode != 0 { return nil }

        for line in res.stdout.split(separator: "\n") {
            if line.first == "p" {
                let num = line.dropFirst()
                if let v = Int32(num) { return v }
            }
        }
        return nil
    }

    private func psCommandLine(pid: Int32) -> String {
        let res = runProcessSync(exe: psPath, args: [
            "-p", "\(pid)",
            "-o", "command="
        ])
        return res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesOurTunnelCommandLine(_ cmd: String) -> Bool {
        let target = "\(user)@\(host)"
        let portOpt = "-p \(sshPort)"

        guard cmd.contains("ssh") else { return false }
        guard cmd.contains(target) else { return false }
        guard cmd.contains(portOpt) else { return false }

        for f in forwardRules {
            let forward = "-L \(f.localPort):\(f.remoteHost):\(f.remotePort)"
            if !cmd.contains(forward) { return false }
        }

        return true
    }

    private func killPid(_ pid: Int32) -> Bool {
        let res = runProcessSync(exe: killPath, args: ["-TERM", "\(pid)"])
        return res.exitCode == 0
    }

    private func startInternal() {
        guard process == nil else { return }

        guard !forwardRules.isEmpty else {
            status = "Error: cap regla de port definida"
            return
        }

        var parsed: [(UInt16, String, UInt16)] = []
        for f in forwardRules {
            guard let lp = UInt16(f.localPort), let rp = UInt16(f.remotePort) else {
                status = "Error: ports invàlids"
                return
            }
            parsed.append((lp, f.remoteHost, rp))
        }

        let state = detectCurrentState()
        switch state {
        case .activeOursControlMaster:
            externalMatchingPid = nil
            isRunning = true
            status = "Actiu (localhost:\(localPortsSummary))"
            maybeMountSMBForForwardRules()
            startTimer()
            return

        case .activeMatchesConfigByPid(let pid):
            externalMatchingPid = pid
            isRunning = true
            status = "Actiu (localhost:\(localPortsSummary))"
            maybeMountSMBForForwardRules()
            startTimer()
            return

        case .portUsedByOther:
            externalMatchingPid = nil
            isRunning = false
            status = "Error: port local ocupat (\(localPortsSummary))"
            appendLog("[error] Local port in use by another process.\n")
            stopTimer()
            return

        case .stopped:
            break
        }

        status = "Connectant…"

        let p = Process()
        p.executableURL = URL(fileURLWithPath: sshPath)
        var args = [
            "-N", "-T",
            "-i", keyPath,
            "-p", sshPort
        ]
        for (lp, rHost, rp) in parsed {
            args += ["-L", "\(lp):\(rHost):\(rp)"]
        }
        args += [
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=10",
            "-o", "ServerAliveCountMax=3",
            "-o", "ConnectTimeout=5",
            "-o", "ConnectionAttempts=1",
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ControlMaster=yes",
            "-o", "ControlPersist=yes",
            "-o", "ControlPath=\(controlSocketPath)",
            "\(user)@\(host)"
        ]
        p.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor [weak self] in self?.appendLog(text) }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor [weak self] in self?.appendLog(text) }
        }

        p.terminationHandler = { [weak self] proc in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                self.process = nil
                self.isRunning = false
                self.stopTimer()

                if self.stopRequested {
                    self.status = "Aturat"
                    return
                }

                if self.isUnknownHostFailure(self.logText), !self.didAttemptKnownHostsFix {
                    self.didAttemptKnownHostsFix = true
                    self.status = "Afegint host a known_hosts…"

                    let ok = self.addHostToKnownHosts()
                    if ok {
                        self.appendLog("\n[info] Added host key to ~/.ssh/known_hosts\n")
                        self.status = "Connectant…"
                        self.startInternal()
                        return
                    } else {
                        self.appendLog("\n[error] Failed to add host key to ~/.ssh/known_hosts\n")
                        self.status = "Error: no puc afegir host a known_hosts"
                        return
                    }
                }

                let st = self.detectCurrentState()
                switch st {
                case .activeOursControlMaster:
                    self.externalMatchingPid = nil
                    self.isRunning = true
                    self.status = "Actiu (localhost:\(self.localPortsSummary))"
                    self.maybeMountSMBForForwardRules()
                    self.startTimer()
                    return

                case .activeMatchesConfigByPid(let pid):
                    self.externalMatchingPid = pid
                    self.isRunning = true
                    self.status = "Actiu (localhost:\(self.localPortsSummary))"
                    self.maybeMountSMBForForwardRules()
                    self.startTimer()
                    return

                case .portUsedByOther:
                    self.externalMatchingPid = nil
                    self.status = "Error: port local ocupat (\(self.localPortsSummary))"
                    return

                case .stopped:
                    break
                }

                let kind = self.classifyFailure(self.logText)

                switch kind {
                case .addressInUse, .authOrKey, .config:
                    self.status = self.statusFor(kind: kind)
                    return
                case .unknownHost:
                    self.status = "Error: host key"
                    if self.autoReconnect { self.scheduleReconnect() }
                    return
                case .transient, .other:
                    self.status = "Error (ssh \(proc.terminationStatus))"
                    if self.autoReconnect { self.scheduleReconnect() }
                    return
                }
            }
        }

        do {
            try p.run()
            process = p
            isRunning = true
            startTimer()
        } catch {
            appendLog("[error] Cannot execute ssh\n")
            status = "Error: no puc executar ssh"
            if autoReconnect && !stopRequested { scheduleReconnect() }
        }
    }

    private enum FailureKind {
        case unknownHost
        case addressInUse
        case authOrKey
        case config
        case transient
        case other
    }

    private func statusFor(kind: FailureKind) -> String {
        switch kind {
        case .addressInUse:
            return "Error: port local ocupat (\(localPortsSummary))"
        case .authOrKey:
            return "Error: autenticació/clau"
        case .config:
            return "Error: configuració ssh"
        default:
            return "Error"
        }
    }

    private func classifyFailure(_ text: String) -> FailureKind {
        let s = text.lowercased()

        if s.contains("the authenticity of host") ||
            s.contains("are you sure you want to continue connecting") ||
            s.contains("host key verification failed") {
            return .unknownHost
        }

        if s.contains("address already in use") ||
            s.contains("cannot listen to port") ||
            s.contains("could not request local forwarding") {
            return .addressInUse
        }

        if s.contains("permission denied") ||
            s.contains("private key file") ||
            (s.contains("no such file or directory") && s.contains(".ssh")) ||
            s.contains("bad permissions") ||
            (s.contains("identity file") && s.contains("not accessible")) {
            return .authOrKey
        }

        if s.contains("bad configuration option") || s.contains("unknown option") {
            return .config
        }

        if s.contains("connection timed out") ||
            s.contains("operation timed out") ||
            s.contains("connection reset by peer") ||
            s.contains("broken pipe") ||
            s.contains("connection refused") ||
            s.contains("network is unreachable") ||
            s.contains("no route to host") {
            return .transient
        }

        return .other
    }

    private func isUnknownHostFailure(_ text: String) -> Bool {
        let s = text.lowercased()
        return s.contains("the authenticity of host") ||
               s.contains("are you sure you want to continue connecting") ||
               s.contains("host key verification failed")
    }

    private func addHostToKnownHosts() -> Bool {
        guard let port = Int(sshPort) else { return false }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let sshDir = home.appendingPathComponent(".ssh", isDirectory: true)
        let knownHosts = sshDir.appendingPathComponent("known_hosts", isDirectory: false)

        do {
            try FileManager.default.createDirectory(at: sshDir, withIntermediateDirectories: true)

            let scan = Process()
            scan.executableURL = URL(fileURLWithPath: keyscanPath)
            scan.arguments = ["-p", String(port), host]

            let out = Pipe()
            scan.standardOutput = out
            scan.standardError = Pipe()

            try scan.run()
            scan.waitUntilExit()
            if scan.terminationStatus != 0 { return false }

            let data = out.fileHandleForReading.readDataToEndOfFile()
            if data.isEmpty { return false }

            if !FileManager.default.fileExists(atPath: knownHosts.path) {
                FileManager.default.createFile(atPath: knownHosts.path, contents: Data())
            }

            let fh = try FileHandle(forWritingTo: knownHosts)
            try fh.seekToEnd()
            try fh.write(contentsOf: data)
            try fh.write(contentsOf: Data("\n".utf8))
            try fh.close()
            return true
        } catch {
            return false
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()

        failures += 1
        let raw = pow(2.0, Double(failures))
        let delay = min(raw, 60.0)

        status = "Reintentant en \(Int(delay))s…"

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled { return }

            await MainActor.run {
                guard let self = self else { return }
                if self.stopRequested { return }
                self.startInternal()
            }
        }
    }

    private func startTimer() {
        if timer != nil { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatus()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateStatus() {
        // Avoid brief "Aturat" flicker while ssh is still negotiating or reconnecting.
        if isInTransientState && (process != nil || reconnectTask != nil) {
            return
        }

        let st = detectCurrentState()
        switch st {
        case .activeOursControlMaster:
            externalMatchingPid = nil
            isRunning = true
            status = "Actiu (localhost:\(localPortsSummary))"
            maybeMountSMBForForwardRules()
        case .activeMatchesConfigByPid(let pid):
            externalMatchingPid = pid
            isRunning = true
            status = "Actiu (localhost:\(localPortsSummary))"
            maybeMountSMBForForwardRules()
        case .portUsedByOther:
            externalMatchingPid = nil
            isRunning = false
            status = "Error: port local ocupat (\(localPortsSummary))"
        case .stopped:
            externalMatchingPid = nil
            isRunning = false
            status = "Aturat"
        }
    }

    private var isInTransientState: Bool {
        status.hasPrefix("Connectant") ||
        status.hasPrefix("Afegint host") ||
        status.hasPrefix("Reintentant")
    }

    private struct SyncResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func runProcessSync(exe: String, args: [String]) -> SyncResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args

        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err

        do { try p.run() } catch {
            return SyncResult(exitCode: -1, stdout: "", stderr: "\(error)")
        }

        p.waitUntilExit()
        let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return SyncResult(exitCode: p.terminationStatus, stdout: o, stderr: e)
    }

    var statusLabel: String {
        if status.hasPrefix("Actiu") { return "Actiu" }
        if status.hasPrefix("Connectant") { return "Connectant" }
        if status.hasPrefix("Reintentant") { return "Connectant" }
        if status.hasPrefix("Afegint host") { return "Connectant" }
        if status.hasPrefix("Aturat") { return "Aturat" }
        return "Error"
    }

    var statusColor: Color {
        if status.hasPrefix("Actiu") { return .green }
        if status.hasPrefix("Connectant") || status.hasPrefix("Reintentant") || status.hasPrefix("Afegint host") { return .orange }
        if status.hasPrefix("Aturat") { return .red }
        return .gray
    }
}

@MainActor
final class SSHConfiguration: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var connection: SSHConnectionController

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
            self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Connexió"
            self.connection = try container.decodeIfPresent(SSHConnectionController.Snapshot.self, forKey: .connection)
                ?? SSHConnectionController.Snapshot(
                    host: "",
                    user: "",
                    sshPort: "",
                    keyPath: "",
                    forwardRules: [
                        PortForwardRule(
                            name: "Regla 1",
                            localPort: "5901",
                            remoteHost: "localhost",
                            remotePort: "5900"
                        )
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
    private enum LoadResult {
        case missing
        case loaded([SSHConfiguration])
        case unreadable
    }

    @Published var configurations: [SSHConfiguration]
    @Published var selectedID: UUID?
    private var cancellables: Set<AnyCancellable> = []
    private var connectionCancellables: [UUID: AnyCancellable] = [:]
    private var saveWorkItem: DispatchWorkItem?
    private let saveURL: URL
    private var needsUnreadableBackup = false

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("SSH-TunelApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        saveURL = dir.appendingPathComponent("configs.json")

        switch Self.loadConfigs(from: saveURL) {
        case .loaded(let loaded):
            configurations = loaded
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
                self?.attachObservers()
                self?.scheduleSave()
            }
            .store(in: &cancellables)
    }

    var selectedConfiguration: SSHConfiguration? {
        guard let id = selectedID else { return nil }
        return configurations.first { $0.id == id }
    }

    func addConfiguration() {
        let idx = configurations.count + 1
        let cfg = SSHConfiguration(name: "Connexió \(idx)", defaultLocalPort: "590\(idx)")
        configurations.append(cfg)
        selectedID = cfg.id
        scheduleSave()
    }

    func removeSelected() {
        guard let id = selectedID else { return }
        guard let idx = configurations.firstIndex(where: { $0.id == id }) else { return }

        let cfg = configurations[idx]
        cfg.connection.stop()

        configurations.remove(at: idx)

        if configurations.isEmpty {
            selectedID = nil
            scheduleSave()
        } else {
            let newIndex = min(idx, configurations.count - 1)
            selectedID = configurations[newIndex].id
            scheduleSave()
        }
    }

    private func attachObservers() {
        connectionCancellables.values.forEach { $0.cancel() }
        connectionCancellables.removeAll()

        for cfg in configurations {
            let c = cfg.connection.objectWillChange
                .sink { [weak self] _ in self?.scheduleSave() }
            connectionCancellables[cfg.id] = c
        }
    }

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.save()
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func save() {
        guard prepareUnreadableBackupIfNeeded() else { return }

        let snapshots = configurations.map { cfg -> SSHConfiguration.Snapshot in
            var snap = cfg.snapshot()
            snap.id = cfg.id
            return snap
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(snapshots)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            // ignore errors silently for now
        }
    }

    private func prepareUnreadableBackupIfNeeded() -> Bool {
        guard needsUnreadableBackup else { return true }
        guard FileManager.default.fileExists(atPath: saveURL.path) else {
            needsUnreadableBackup = false
            return true
        }

        let backupURL = Self.makeRecoveryBackupURL(for: saveURL)
        do {
            try FileManager.default.copyItem(at: saveURL, to: backupURL)
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
            return .loaded(snaps.map { SSHConfiguration(snapshot: $0) })
        } catch {
            return .unreadable
        }
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

struct ContentView: View {
    @EnvironmentObject private var store: SSHConfigStore
    @State private var sidebarWidth: CGFloat = 220
    @State private var sidebarDragOrigin: CGFloat?
    private let minSidebarWidth: CGFloat = 150
    private let maxSidebarWidth: CGFloat = 320

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Configuracions SSH").font(.headline)
                    Spacer()
                }

                List(selection: $store.selectedID) {
                    ForEach(store.configurations) { cfg in
                        ConfigRow(configuration: cfg, connection: cfg.connection)
                            .tag(cfg.id)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack {
                    Button(action: store.addConfiguration) {
                        Text("+ Afegir")
                    }
                    .help("Afegir configuració")

                    Spacer()

                    Button(role: .destructive, action: store.removeSelected) {
                        Label("Eliminar", systemImage: "trash")
                    }
                    .disabled(store.selectedConfiguration == nil)
                }
            }
            .padding(12)
            .frame(width: sidebarWidth)
            .frame(maxHeight: .infinity)
            .background(Color.gray.opacity(0.12))

            ZStack {
                Divider()
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle()) // larger hit area for drag
            }
            .frame(width: 8)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if sidebarDragOrigin == nil {
                            sidebarDragOrigin = sidebarWidth
                        }
                        let base = sidebarDragOrigin ?? sidebarWidth
                        let proposed = base + value.translation.width
                        sidebarWidth = min(max(proposed, minSidebarWidth), maxSidebarWidth)
                    }
                    .onEnded { _ in
                        sidebarDragOrigin = nil
                    }
            )

            if let cfg = store.selectedConfiguration {
                ConnectionDetailView(configuration: cfg, connection: cfg.connection)
                    .frame(minWidth: 520)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack {
                    Text("Selecciona o crea una configuració").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }
}

private struct ConnectionDetailView: View {
    @ObservedObject var configuration: SSHConfiguration
    @ObservedObject var connection: SSHConnectionController

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nom configuració")
                .fontWeight(.bold)
            TextField("Nom de la configuració", text: $configuration.name)
                .textFieldStyle(.roundedBorder)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    row("Host", $connection.host)
                    row("Usuari", $connection.user)
                    row("Port", $connection.sshPort, width: 80)
                    row("Clau", $connection.keyPath)
                }
                .textFieldStyle(.roundedBorder)
            } label: {
                Text("Connexió SSH")
                    .font(.body)
                    .fontWeight(.bold)
            }
            .disabled(connection.isRunning)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($connection.forwardRules) { $rule in
                        HStack(spacing: 8) {
                            Text("Nom").frame(width: 40, alignment: .leading)
                            TextField("", text: $rule.name).frame(width: 130)
                            Text("Local").frame(width: 50, alignment: .leading)
                            TextField("", text: $rule.localPort).frame(width: 70)
                            Text("→")
                            TextField("", text: $rule.remoteHost)
                            TextField("", text: $rule.remotePort).frame(width: 70)

                            Button(role: .destructive) {
                                connection.removeForwardRule(id: rule.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .help("Eliminar regla")
                            .disabled(connection.isRunning || connection.forwardRules.count == 1)
                        }
                    }

                    HStack {
                        Button {
                            connection.addForwardRule()
                        } label: {
                            Label("Afegir regla", systemImage: "plus")
                        }
                        .disabled(connection.isRunning)

                        Spacer()
                    }
                }
                .textFieldStyle(.roundedBorder)
            } label: {
                Text("Regles de reenviament de port")
                    .font(.body)
                    .fontWeight(.bold)
            }
            .disabled(connection.isRunning)

            Toggle("Reconnectar automàticament si es perd la connexió", isOn: $connection.autoReconnect)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView {
                        Text(connection.logText.isEmpty ? "—" : connection.logText)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .padding(.vertical, 6)
                    }
                    .frame(height: 140)

                    HStack {
                        Button("Netejar") { connection.clearLog() }
                        Spacer()
                    }
                }
            } label: {
                Text("Sortida (ssh)")
                    .font(.body)
                    .fontWeight(.bold)
            }

            HStack(spacing: 10) {
                Button("Activar") { connection.start() }.disabled(connection.isRunning)
                Button("Desactivar") { connection.stop() }.disabled(!connection.isRunning)
                Button("Refrescar") { connection.checkInitialState() }

                Spacer()

                HStack(spacing: 6) {
                    Circle().fill(connection.statusColor).frame(width: 10, height: 10)
                    Text(connection.statusLabel).foregroundStyle(connection.statusColor)
                }
            }

        }
        .padding(16)
        .onAppear { connection.checkInitialState() }
    }

    private func row(_ label: String, _ binding: Binding<String>, width: CGFloat? = nil) -> some View {
        HStack {
            Text(label).frame(width: 70, alignment: .leading)
            TextField("", text: binding).frame(width: width)
        }
    }
}

private struct ConfigRow: View {
    @ObservedObject var configuration: SSHConfiguration
    @ObservedObject var connection: SSHConnectionController

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connection.statusColor)
                .frame(width: 8, height: 8)
            Text(configuration.name)
                .lineLimit(1)
        }
    }
}
