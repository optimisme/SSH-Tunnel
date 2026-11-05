//  SSHConnectionController.swift

import SwiftUI
import Foundation
import AppKit
import Combine
import Darwin

enum TunnelPhase: Equatable {
    case stopped
    case connecting
    case retrying(seconds: Int)
    case active
    case stopping
    case error(TunnelIssue)
}

/// Why a tunnel is in the error state. Kept typed so the UI text is localized in one place.
enum TunnelIssue: Equatable {
    case missingHost
    case invalidSSHPort
    case noRules
    case invalidPorts(rule: String)
    case missingRemoteHost(rule: String)
    case duplicateLocalPort(Int)
    case hostKeyChanged
    case localPortInUse(String)
    case authentication
    case sshConfiguration
    case sshExited(Int)
    case connectionLost
    case cannotRunSSH

    var message: String {
        switch self {
        case .missingHost:
            return String(localized: "Enter a host", comment: "Tunnel error")
        case .invalidSSHPort:
            return String(localized: "Invalid SSH port", comment: "Tunnel error")
        case .noRules:
            return String(localized: "No port forwarding rules", comment: "Tunnel error")
        case .invalidPorts(let rule):
            return String(localized: "Invalid ports in “\(rule)”", comment: "Tunnel error; the argument is a rule name")
        case .missingRemoteHost(let rule):
            return String(localized: "Missing remote host in “\(rule)”", comment: "Tunnel error; the argument is a rule name")
        case .duplicateLocalPort(let port):
            return String(localized: "Local port \(port) is used twice", comment: "Tunnel error")
        case .hostKeyChanged:
            return String(localized: "The host key changed (check ~/.ssh/known_hosts)", comment: "Tunnel error")
        case .localPortInUse(let ports):
            return String(localized: "Local port in use (\(ports))", comment: "Tunnel error; the argument is a list of ports")
        case .authentication:
            return String(localized: "Authentication failed (check the key or ssh-agent)", comment: "Tunnel error")
        case .sshConfiguration:
            return String(localized: "SSH configuration error", comment: "Tunnel error")
        case .sshExited(let code):
            return String(localized: "ssh exited (code \(code))", comment: "Tunnel error; the argument is an exit status")
        case .connectionLost:
            return String(localized: "Connection lost", comment: "Tunnel error")
        case .cannotRunSSH:
            return String(localized: "Cannot run ssh", comment: "Tunnel error")
        }
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

    @Published private(set) var phase: TunnelPhase = .stopped

    @Published var host = ""
    @Published var user = ""
    @Published var sshPort = ""
    @Published var keyPath = ""
    @Published var forwardRules: [PortForwardRule]
    @Published var autoReconnect = false

    @Published private(set) var logText = ""

    private var process: Process?
    private var timer: Timer?
    private var reconnectTask: Task<Void, Never>?
    private var failures = 0
    private var isProbing = false
    private var externalMatchingPid: Int32?
    private var attemptedSMBMountPorts: Set<String> = []
    /// Output of the current ssh attempt only, used to classify failures.
    private var attemptLog = ""
    /// Bumped on every user start/stop so stale async results are discarded.
    private var generation = 0
    private var resumeAfterWake = false

    private static let maxLogCharacters = 40_000
    static let defaultKeyPath = "~/.ssh/id_rsa"

    init(defaultLocalPort: String) {
        self.keyPath = Self.defaultKeyPath
        self.forwardRules = [PortForwardRule(name: Self.ruleName(1), localPort: defaultLocalPort, remoteHost: "localhost", remotePort: "5900")]
    }

    static func ruleName(_ index: Int) -> String {
        String(localized: "Rule \(index)", comment: "Default name of a port forwarding rule")
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

    // MARK: - Public state

    /// True while a tunnel is up or being set up/torn down (fields are locked).
    var isRunning: Bool {
        switch phase {
        case .stopped, .error: return false
        default: return true
        }
    }

    var isActive: Bool { phase == .active }

    var statusLabel: String {
        switch phase {
        case .active: return String(localized: "Active", comment: "Tunnel status")
        case .connecting, .retrying: return String(localized: "Connecting", comment: "Tunnel status")
        case .stopping: return String(localized: "Stopping", comment: "Tunnel status")
        case .stopped: return String(localized: "Stopped", comment: "Tunnel status")
        case .error: return String(localized: "Error", comment: "Tunnel status")
        }
    }

    var statusDetail: String {
        switch phase {
        case .active: return "localhost:\(localPortsSummary)"
        case .connecting: return String(localized: "Connecting…", comment: "Tunnel status detail")
        case .retrying(let s): return String(localized: "Retrying in \(s) s…", comment: "Tunnel status detail; s = seconds")
        case .stopping: return String(localized: "Stopping…", comment: "Tunnel status detail")
        case .stopped: return ""
        case .error(let issue): return issue.message
        }
    }

    var statusColor: Color {
        switch phase {
        case .active: return .green
        case .connecting, .retrying, .stopping: return .orange
        case .stopped: return .gray
        case .error: return .red
        }
    }

    // MARK: - User actions

    func start(clearLog: Bool = true) {
        guard !isRunning else { return }
        generation += 1
        failures = 0
        externalMatchingPid = nil
        attemptedSMBMountPorts.removeAll()
        if clearLog { logText = "" }
        connect()
    }

    func stop() {
        Task { await performStop() }
    }

    /// Stops the tunnel and returns once ssh has been told to exit (used on quit).
    func stopAndWait() async {
        guard isRunning else { return }
        await performStop()
    }

    /// Re-inspects the system (e.g. on launch, or to adopt a tunnel started outside the app).
    func refresh() {
        guard !isProbing, process == nil, reconnectTask == nil, phase != .stopping else { return }
        guard let spec = makeSpec() else { return }
        let gen = generation
        isProbing = true
        Task {
            let state = await ProcessRunner.background { TunnelProbe.detect(spec) }
            self.isProbing = false
            guard gen == self.generation else { return }
            switch state {
            case .activeOursControlMaster, .activeMatchesConfigByPid, .portUsedByOther:
                self.apply(state)
            case .stopped:
                if self.phase == .active { self.apply(.stopped) } else { self.phase = .stopped }
            }
        }
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
        guard !isRunning, forwardRules.count > 1 else { return }
        forwardRules.removeAll { $0.id == id }
    }

    /// Moves the rule at `source` so it ends up at index `destination` (clamped).
    func moveForwardRule(from source: Int, to destination: Int) {
        guard !isRunning, forwardRules.indices.contains(source) else { return }
        let target = min(max(destination, 0), forwardRules.count - 1)
        guard target != source else { return }
        let rule = forwardRules.remove(at: source)
        forwardRules.insert(rule, at: target)
    }

    // MARK: - Sleep / wake

    func systemWillSleep() {
        resumeAfterWake = isRunning && phase != .stopping
        stopTimer()
        reconnectTask?.cancel()
        reconnectTask = nil
    }

    func systemDidWake() {
        guard resumeAfterWake else { return }
        resumeAfterWake = false

        if autoReconnect {
            // The TCP connection almost certainly died during sleep, but the ssh
            // master may not notice for ~30s. Restart it right away instead.
            appendLog("[info] " + String(localized: "Woke from sleep: restarting the tunnel", comment: "Log line"))
            Task {
                await self.performStop()
                try? await Task.sleep(nanoseconds: 2_000_000_000) // let the network come back
                self.start(clearLog: false)
            }
        } else if phase == .active || process != nil {
            startTimer()
            refresh()
        } else {
            phase = .stopped
        }
    }

    // MARK: - Connect / stop

    private func connect() {
        guard process == nil else { return }
        if let problem = validationError() {
            appendLog("[error] \(problem.message)")
            phase = .error(problem)
            return
        }
        guard let spec = makeSpec() else { return }

        phase = .connecting
        let gen = generation
        Task {
            let state = await ProcessRunner.background { TunnelProbe.detect(spec) }
            guard gen == self.generation, self.phase == .connecting else { return }
            if state == .stopped {
                self.launchSSH(gen: gen)
            } else {
                if state == .portUsedByOther {
                    self.appendLog("[error] " + String(localized: "A local port is in use by another process.", comment: "Log line"))
                }
                self.apply(state)
            }
        }
    }

    private func launchSSH(gen: Int) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Tools.ssh)

        var args = ["-N", "-T"]
        let key = keyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { args += ["-i", (key as NSString).expandingTildeInPath] }
        let port = sshPort.trimmingCharacters(in: .whitespacesAndNewlines)
        if !port.isEmpty { args += ["-p", port] }
        for f in forwardSpecs { args += ["-L", f] }
        args += [
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=10",
            "-o", "ServerAliveCountMax=3",
            "-o", "ConnectTimeout=30",
            "-o", "ConnectionAttempts=1",
            "-o", "BatchMode=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ControlMaster=yes",
            "-o", "ControlPersist=yes",
            "-o", "ControlPath=\(controlSocketPath)",
            sshTarget
        ]
        p.arguments = args
        p.standardInput = FileHandle.nullDevice

        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe

        let logHandler: @Sendable (FileHandle) -> Void = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            let text = String(data: data, encoding: .utf8) ?? ""
            Task { @MainActor [weak self] in self?.appendLog(text, attempt: true) }
        }
        outPipe.fileHandleForReading.readabilityHandler = logHandler
        errPipe.fileHandleForReading.readabilityHandler = logHandler

        let procID = ObjectIdentifier(p)
        p.terminationHandler = { [weak self] proc in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            let code = proc.terminationStatus
            Task { @MainActor [weak self] in
                // Give in-flight log chunks a moment to land before classifying.
                try? await Task.sleep(nanoseconds: 300_000_000)
                await self?.handleTermination(procID: procID, exitCode: code, gen: gen)
            }
        }

        attemptLog = ""
        do {
            try p.run()
            process = p
            startTimer()
        } catch {
            appendLog("[error] " + String(localized: "Cannot run ssh: \(error.localizedDescription)", comment: "Log line"))
            phase = .error(.cannotRunSSH)
        }
    }

    private func handleTermination(procID: ObjectIdentifier, exitCode: Int32, gen: Int) async {
        guard let current = process, ObjectIdentifier(current) == procID else { return }
        process = nil
        guard gen == generation, let spec = makeSpec() else { return }

        // With ControlPersist the foreground ssh may exit while the master keeps running.
        let state = await ProcessRunner.background { TunnelProbe.detect(spec) }
        guard gen == generation, phase != .stopping else { return }
        if state != .stopped {
            apply(state)
            return
        }

        stopTimer()
        let kind = Self.classifyFailure(attemptLog)
        switch kind {
        case .hostKeyChanged:
            phase = .error(.hostKeyChanged)
        case .addressInUse:
            phase = .error(.localPortInUse(localPortsSummary))
        case .authOrKey:
            phase = .error(.authentication)
        case .config:
            phase = .error(.sshConfiguration)
        case .transient, .other:
            if autoReconnect {
                scheduleReconnect()
            } else {
                phase = .error(.sshExited(Int(exitCode)))
            }
        }
    }

    private func performStop() async {
        generation += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        stopTimer()
        phase = .stopping

        let spec = makeSpec()
        let targets = smbTargets()
        let pid = externalMatchingPid
        externalMatchingPid = nil
        let proc = process
        process = nil

        let log = await ProcessRunner.background { () -> [String] in
            var log = SMB.unmount(targets: targets)
            let exited = spec.map { TunnelProbe.controlExit($0) } ?? false
            if !exited, let pid {
                if kill(pid, SIGTERM) != 0 {
                    log.append("[error] " + String(localized: "Could not stop ssh process \(Int(pid))", comment: "Log line"))
                }
            }
            return log
        }
        log.forEach { appendLog($0) }

        proc?.terminate()
        attemptedSMBMountPorts.removeAll()
        phase = .stopped
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()

        failures += 1
        let delay = min(pow(2.0, Double(failures)), 60.0)
        phase = .retrying(seconds: Int(delay))

        let gen = generation
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, gen == self.generation else { return }
            self.reconnectTask = nil
            self.connect()
        }
    }

    // MARK: - State application

    private func apply(_ state: DetectedState) {
        switch state {
        case .activeOursControlMaster:
            externalMatchingPid = nil
            becameActive()
        case .activeMatchesConfigByPid(let pid):
            externalMatchingPid = pid
            becameActive()
        case .portUsedByOther:
            externalMatchingPid = nil
            stopTimer()
            phase = .error(.localPortInUse(localPortsSummary))
        case .stopped:
            externalMatchingPid = nil
            stopTimer()
            if phase == .active {
                appendLog("[info] " + TunnelIssue.connectionLost.message)
                if autoReconnect {
                    scheduleReconnect()
                } else {
                    phase = .error(.connectionLost)
                }
            } else {
                phase = .stopped
            }
        }
    }

    private func becameActive() {
        phase = .active
        failures = 0
        maybeMountSMBForForwardRules()
        startTimer()
    }

    // MARK: - Polling

    private func startTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard !isProbing, phase == .active || phase == .connecting, let spec = makeSpec() else { return }
        let gen = generation
        isProbing = true
        Task {
            let state = await ProcessRunner.background { TunnelProbe.detect(spec) }
            self.isProbing = false
            guard gen == self.generation else { return }

            switch self.phase {
            case .connecting:
                // Only promote to active; failures are reported by the termination handler.
                if case .activeOursControlMaster = state { self.apply(state) }
                if case .activeMatchesConfigByPid = state { self.apply(state) }
            case .active:
                // If our foreground ssh is still alive, let its termination handler decide.
                if state == .stopped && self.process != nil { return }
                self.apply(state)
            default:
                break
            }
        }
    }

    // MARK: - SMB

    private func maybeMountSMBForForwardRules() {
        for rule in forwardRules where rule.remotePort.trimmed == "445" {
            let local = rule.localPort.trimmed
            guard !attemptedSMBMountPorts.contains(local) else { continue }
            attemptedSMBMountPorts.insert(local)

            guard let url = SMB.homeURL(user: user, localPort: local) else {
                appendLog("[error] " + String(localized: "Could not build the SMB address for local port \(local)", comment: "Log line"))
                continue
            }
            if NSWorkspace.shared.open(url) {
                appendLog("[info] " + String(localized: "Opening the SMB share in Finder: \(url.absoluteString)", comment: "Log line"))
            } else {
                appendLog("[error] " + String(localized: "Finder could not open \(url.absoluteString)", comment: "Log line"))
            }
        }
    }

    private func smbTargets() -> Set<SMBTarget> {
        Set(forwardRules
            .filter { $0.remotePort.trimmed == "445" }
            .compactMap { SMB.homeURL(user: user, localPort: $0.localPort.trimmed) }
            .compactMap(SMB.target(from:)))
    }

    // MARK: - Helpers

    /// `user@host`, or just `host` so ssh takes the user from ~/.ssh/config (or the login name).
    private var sshTarget: String { user.trimmed.isEmpty ? host.trimmed : "\(user.trimmed)@\(host.trimmed)" }

    private var localPortsSummary: String {
        forwardRules.map { $0.localPort }.joined(separator: ",")
    }

    private var forwardSpecs: [String] {
        forwardRules.map { "\($0.localPort.trimmed):\($0.remoteHost.trimmed):\($0.remotePort.trimmed)" }
    }

    var controlSocketPath: String {
        // NOTE: keep this format stable so tunnels started by previous versions are still recognised.
        let forwardRulesKey = forwardRules
            .map { "L\($0.localPort)->\($0.remoteHost):\($0.remotePort)" }
            .sorted()
            .joined(separator: "|")
        let base = "\(user)@\(host):\(sshPort)|\(forwardRulesKey)"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.ssh/tunnelctl_\(Self.stableShortHash(base)).sock"
    }

    static func stableShortHash(_ s: String) -> String {
        var hash: UInt64 = 14695981039346656037
        for b in s.utf8 {
            hash ^= UInt64(b)
            hash &*= 1099511628211
        }
        return String(format: "%016llx", hash)
    }

    private func makeSpec() -> TunnelSpec? {
        guard !host.trimmed.isEmpty else { return nil }
        return TunnelSpec(
            target: sshTarget,
            sshPort: sshPort.trimmed,
            localPorts: forwardRules.compactMap { UInt16($0.localPort.trimmed) },
            forwards: forwardSpecs,
            controlSocketPath: controlSocketPath
        )
    }

    func validationError() -> TunnelIssue? {
        if host.trimmed.isEmpty { return .missingHost }
        if !sshPort.trimmed.isEmpty, (UInt16(sshPort.trimmed) ?? 0) == 0 { return .invalidSSHPort }
        if forwardRules.isEmpty { return .noRules }
        var seen = Set<UInt16>()
        for r in forwardRules {
            guard let lp = UInt16(r.localPort.trimmed), lp > 0,
                  let rp = UInt16(r.remotePort.trimmed), rp > 0 else { return .invalidPorts(rule: r.name) }
            if r.remoteHost.trimmed.isEmpty { return .missingRemoteHost(rule: r.name) }
            if !seen.insert(lp).inserted { return .duplicateLocalPort(Int(lp)) }
        }
        return nil
    }

    private func appendLog(_ s: String, attempt: Bool = false) {
        let t = s.trimmingCharacters(in: .newlines)
        guard !t.isEmpty else { return }
        if attempt { attemptLog += t + "\n" }
        if !logText.isEmpty { logText += "\n" }
        logText += t
        if logText.utf8.count > Self.maxLogCharacters {
            logText = String(logText.suffix(Self.maxLogCharacters / 2))
        }
    }

    private func suggestedLocalPort() -> String {
        let used = Set(forwardRules.compactMap { Int($0.localPort) })
        var port = 5901
        while used.contains(port) { port += 1 }
        return "\(port)"
    }

    private func suggestedRuleName() -> String {
        let used = Set(forwardRules.map { $0.name.trimmed })
        var idx = 1
        while used.contains(Self.ruleName(idx)) { idx += 1 }
        return Self.ruleName(idx)
    }

    // MARK: - Failure classification

    enum FailureKind {
        case hostKeyChanged
        case addressInUse
        case authOrKey
        case config
        case transient
        case other
    }

    static func classifyFailure(_ text: String) -> FailureKind {
        let s = text.lowercased()

        if s.contains("host key verification failed") ||
            s.contains("remote host identification has changed") {
            return .hostKeyChanged
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
        if s.contains("bad configuration option") || s.contains("unknown option") || s.contains("bad port") {
            return .config
        }
        if s.contains("timed out") ||
            s.contains("connection reset by peer") ||
            s.contains("broken pipe") ||
            s.contains("connection refused") ||
            s.contains("network is unreachable") ||
            s.contains("no route to host") ||
            s.contains("could not resolve hostname") ||
            s.contains("server not responding") {
            return .transient
        }
        return .other
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
