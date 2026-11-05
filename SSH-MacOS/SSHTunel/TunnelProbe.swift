//  TunnelProbe.swift
//
//  Blocking inspection helpers (control socket check, lsof, ps, SMB unmount).
//  Everything here is nonisolated and must run off the main thread – use
//  `ProcessRunner.background { … }`.

import Foundation
import Darwin

nonisolated enum Tools {
    static let ssh = "/usr/bin/ssh"
    static let lsof = "/usr/sbin/lsof"
    static let ps = "/bin/ps"
    static let umount = "/sbin/umount"
    static let diskutil = "/usr/sbin/diskutil"
}

/// Value snapshot of everything needed to inspect a tunnel from a background thread.
nonisolated struct TunnelSpec: Sendable {
    let user: String
    let host: String
    let sshPort: String
    let localPorts: [UInt16]
    /// `local:remoteHost:remotePort` strings, exactly as passed to `ssh -L`.
    let forwards: [String]
    let controlSocketPath: String

    var target: String { "\(user)@\(host)" }
}

nonisolated enum DetectedState: Sendable, Equatable {
    case activeOursControlMaster
    case activeMatchesConfigByPid(Int32)
    case portUsedByOther
    case stopped
}

nonisolated enum TunnelProbe {
    static func detect(_ spec: TunnelSpec) -> DetectedState {
        if controlCheck(spec) {
            return .activeOursControlMaster
        }

        for port in spec.localPorts {
            guard let pid = listeningPid(port: port) else { continue }
            let cmd = commandLine(pid: pid)
            return matches(commandLine: cmd, spec: spec) ? .activeMatchesConfigByPid(pid) : .portUsedByOther
        }

        return .stopped
    }

    static func controlCheck(_ spec: TunnelSpec) -> Bool {
        ProcessRunner.runBlocking(Tools.ssh, [
            "-o", "BatchMode=yes",
            "-S", spec.controlSocketPath,
            "-O", "check",
            spec.target
        ], timeout: 5).exitCode == 0
    }

    static func controlExit(_ spec: TunnelSpec) -> Bool {
        ProcessRunner.runBlocking(Tools.ssh, [
            "-o", "BatchMode=yes",
            "-S", spec.controlSocketPath,
            "-O", "exit",
            spec.target
        ], timeout: 5).exitCode == 0
    }

    static func listeningPid(port: UInt16) -> Int32? {
        // -b: avoid kernel calls that can block (stat on dead network mounts).
        // -w: suppress the warnings -b produces.
        let res = ProcessRunner.runBlocking(Tools.lsof, [
            "-nP", "-b", "-w",
            "-iTCP:\(port)",
            "-sTCP:LISTEN",
            "-Fp"
        ], timeout: 5)
        guard res.exitCode == 0 else { return nil }

        for line in res.stdout.split(separator: "\n") where line.first == "p" {
            if let v = Int32(line.dropFirst()) { return v }
        }
        return nil
    }

    static func commandLine(pid: Int32) -> String {
        ProcessRunner.runBlocking(Tools.ps, ["-p", "\(pid)", "-o", "command="], timeout: 3)
            .stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Token-based match so that e.g. `-p 22` does not match `-p 2222`.
    static func matches(commandLine cmd: String, spec: TunnelSpec) -> Bool {
        let tokens = cmd.split(separator: " ").map(String.init)
        guard let exe = tokens.first, (exe as NSString).lastPathComponent == "ssh" else { return false }
        guard tokens.contains(spec.target) else { return false }

        func hasPair(_ flag: String, _ value: String) -> Bool {
            if tokens.contains(flag + value) { return true }
            for (i, t) in tokens.enumerated() where t == flag && i + 1 < tokens.count {
                if tokens[i + 1] == value { return true }
            }
            return false
        }

        let port = spec.sshPort.isEmpty ? "22" : spec.sshPort
        if port != "22" || tokens.contains("-p") {
            guard hasPair("-p", port) else { return false }
        }
        for fwd in spec.forwards where !hasPair("-L", fwd) {
            return false
        }
        return true
    }
}

// MARK: - SMB helpers

nonisolated struct SMBTarget: Hashable, Sendable {
    let user: String
    let host: String
    let port: Int
    let path: String
}

nonisolated enum SMB {
    static func homeURL(user rawUser: String, localPort: String) -> URL? {
        let smbUser = rawUser.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !smbUser.isEmpty, let port = Int(localPort) else { return nil }

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

    static func target(from url: URL) -> SMBTarget? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              (c.scheme ?? "").lowercased() == "smb",
              let host = c.host?.lowercased(), !host.isEmpty,
              let user = c.user, !user.isEmpty,
              let port = c.port
        else { return nil }
        let path = c.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty else { return nil }
        return SMBTarget(user: user, host: host, port: port, path: path)
    }

    static func isMatchingRemountURL(_ remountURL: URL, targets: Set<SMBTarget>) -> Bool {
        guard let c = URLComponents(url: remountURL, resolvingAgainstBaseURL: false),
              (c.scheme ?? "").lowercased() == "smb",
              let host = c.host?.lowercased(), !host.isEmpty,
              let user = c.user, !user.isEmpty
        else { return false }
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

    /// Unmounts every mounted volume served by one of `targets`. Returns log lines.
    static func unmount(targets: Set<SMBTarget>) -> [String] {
        guard !targets.isEmpty else { return [] }
        guard let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeURLForRemountingKey],
            options: [.skipHiddenVolumes]
        ) else { return [] }

        var log: [String] = []
        for mountPoint in mounted {
            guard
                let values = try? mountPoint.resourceValues(forKeys: [.volumeURLForRemountingKey]),
                let remountURL = values.volumeURLForRemounting,
                isMatchingRemountURL(remountURL, targets: targets)
            else { continue }

            let ok = ProcessRunner.runBlocking(Tools.umount, [mountPoint.path], timeout: 10).exitCode == 0
                || ProcessRunner.runBlocking(Tools.diskutil, ["unmount", "force", mountPoint.path], timeout: 15).exitCode == 0
            log.append(ok ? "[info] Unmounted SMB volume: \(mountPoint.path)"
                          : "[error] Could not unmount SMB volume: \(mountPoint.path)")
        }
        return log
    }
}
