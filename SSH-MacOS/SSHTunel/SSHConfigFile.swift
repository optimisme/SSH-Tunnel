//  SSHConfigFile.swift
//
//  Read-only helpers around the user's OpenSSH setup: host aliases declared in
//  ~/.ssh/config, private keys in ~/.ssh and `ssh -G` resolution.
//  Everything here is nonisolated; file and process access must run off the
//  main thread (`ProcessRunner.background { … }`).

import Foundation
import Darwin

nonisolated struct ResolvedSSHHost: Equatable, Sendable {
    var hostName: String
    var user: String
    var port: String
    var identityFiles: [String]
}

nonisolated enum SSHConfigFile {
    static var sshDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh", isDirectory: true)
    }

    // MARK: Host aliases

    /// Concrete `Host` aliases (no wildcards or negations), following `Include`.
    static func hostAliases(configURL: URL = sshDirectory.appendingPathComponent("config")) -> [String] {
        var seenFiles = Set<String>()
        var result: [String] = []
        collectAliases(from: configURL, depth: 0, seenFiles: &seenFiles, into: &result)
        var unique = Set<String>()
        return result.filter { unique.insert($0).inserted }
    }

    private static func collectAliases(from url: URL, depth: Int, seenFiles: inout Set<String>, into result: inout [String]) {
        guard depth < 8, seenFiles.insert(url.standardizedFileURL.path).inserted,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let parsed = parse(text)
        result += parsed.aliases
        for pattern in parsed.includes {
            for path in expandInclude(pattern) {
                collectAliases(from: URL(fileURLWithPath: path), depth: depth + 1, seenFiles: &seenFiles, into: &result)
            }
        }
    }

    /// Parses one ssh_config file. Pure function, used by tests.
    static func parse(_ text: String) -> (aliases: [String], includes: [String]) {
        var aliases: [String] = []
        var includes: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let (keyword, args) = splitDirective(line)
            switch keyword.lowercased() {
            case "host":
                aliases += args.filter { arg in
                    !arg.contains(where: { "*?!".contains($0) })
                }
            case "include":
                includes += args
            default:
                break
            }
        }
        return (aliases, includes)
    }

    /// `Keyword arg1 "arg 2"` or `Keyword=arg`.
    private static func splitDirective(_ line: String) -> (String, [String]) {
        var keyword = ""
        var rest = Substring(line)
        if let idx = line.firstIndex(where: { $0 == " " || $0 == "\t" || $0 == "=" }) {
            keyword = String(line[..<idx])
            rest = line[line.index(after: idx)...]
            rest = rest.drop(while: { $0 == " " || $0 == "\t" || $0 == "=" })
        } else {
            keyword = line
            rest = ""
        }

        var args: [String] = []
        var current = ""
        var inQuotes = false
        var hasToken = false
        for ch in rest {
            if ch == "\"" {
                inQuotes.toggle()
                hasToken = true
            } else if (ch == " " || ch == "\t") && !inQuotes {
                if hasToken { args.append(current) }
                current = ""
                hasToken = false
            } else {
                current.append(ch)
                hasToken = true
            }
        }
        if hasToken { args.append(current) }
        return (keyword, args)
    }

    /// Relative Include paths are relative to ~/.ssh; globs are expanded.
    private static func expandInclude(_ pattern: String) -> [String] {
        var path = (pattern as NSString).expandingTildeInPath
        if !path.hasPrefix("/") { path = sshDirectory.appendingPathComponent(path).path }

        var g = glob_t()
        defer { globfree(&g) }
        guard glob(path, 0, nil, &g) == 0 else { return [] }
        return (0..<Int(g.gl_pathc)).compactMap { i in
            g.gl_pathv[i].flatMap { String(cString: $0) }
        }
    }

    // MARK: Keys

    /// Private keys in ~/.ssh, displayed with a `~/` prefix.
    static func privateKeys(in dir: URL = sshDirectory) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        let ignored: Set<String> = ["config", "known_hosts", "known_hosts.old", "authorized_keys", "environment"]
        return names.sorted().compactMap { name -> String? in
            guard !name.hasPrefix("."), !name.hasSuffix(".pub"), !ignored.contains(name),
                  !name.hasPrefix("tunnelctl_") else { return nil }
            let url = dir.appendingPathComponent(name)
            guard isPrivateKey(url) else { return nil }
            return abbreviatingHome(url.path)
        }
    }

    static func isPrivateKey(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 64),
              let text = String(data: head, encoding: .utf8) else { return false }
        return text.hasPrefix("-----BEGIN") && text.contains("PRIVATE KEY")
    }

    static func abbreviatingHome(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    // MARK: ssh -G

    /// Effective settings for `host` as ssh would use them (reads config only, no network).
    static func resolve(host: String) -> ResolvedSSHHost? {
        let res = ProcessRunner.runBlocking(Tools.ssh, ["-G", host], timeout: 3)
        guard res.exitCode == 0 else { return nil }
        return parseResolved(res.stdout)
    }

    static func parseResolved(_ output: String) -> ResolvedSSHHost? {
        var host = ResolvedSSHHost(hostName: "", user: "", port: "", identityFiles: [])
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "hostname": host.hostName = parts[1]
            case "user": host.user = parts[1]
            case "port": host.port = parts[1]
            case "identityfile": host.identityFiles.append(parts[1])
            default: break
            }
        }
        return host.hostName.isEmpty ? nil : host
    }
}
