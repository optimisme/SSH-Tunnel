import Foundation
import Testing
@testable import SSHTunel

struct SSHConfigFileTests {
    @Test func parsesHostsAndIncludes() {
        let text = """
        # comment
        Include config.d/*
        Host bsd linux
          HostName 192.168.1.196
        Host *.example.com !bad
        Host=web
        host "quoted name" plain
          IdentityFile ~/.ssh/id_ed25519
        Match host foo
        """
        let parsed = SSHConfigFile.parse(text)
        #expect(parsed.aliases == ["bsd", "linux", "web", "quoted name", "plain"])
        #expect(parsed.includes == ["config.d/*"])
    }

    @Test func followsIncludesWithGlobsAndAvoidsLoops() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sshcfg-\(UUID().uuidString)")
        let sub = dir.appendingPathComponent("conf.d")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let main = dir.appendingPathComponent("config")
        try "Host main\nInclude \(sub.path)/*\nInclude \(main.path)\n".write(to: main, atomically: true, encoding: .utf8)
        try "Host a1 main\n".write(to: sub.appendingPathComponent("a.conf"), atomically: true, encoding: .utf8)
        try "Host b1 *\n".write(to: sub.appendingPathComponent("b.conf"), atomically: true, encoding: .utf8)

        #expect(SSHConfigFile.hostAliases(configURL: main) == ["main", "a1", "b1"])
    }

    @Test func missingConfigGivesNoAliases() {
        let url = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")
        #expect(SSHConfigFile.hostAliases(configURL: url).isEmpty)
    }

    @Test func findsPrivateKeysOnly() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("keys-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let header = "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n"
        try header.write(to: dir.appendingPathComponent("id_ed25519"), atomically: true, encoding: .utf8)
        try "-----BEGIN RSA PRIVATE KEY-----\n".write(to: dir.appendingPathComponent("legacy"), atomically: true, encoding: .utf8)
        try "ssh-ed25519 AAAA".write(to: dir.appendingPathComponent("id_ed25519.pub"), atomically: true, encoding: .utf8)
        try "Host x".write(to: dir.appendingPathComponent("config"), atomically: true, encoding: .utf8)
        try "github.com ssh-ed25519".write(to: dir.appendingPathComponent("known_hosts"), atomically: true, encoding: .utf8)

        let keys = SSHConfigFile.privateKeys(in: dir).map { ($0 as NSString).lastPathComponent }
        #expect(keys == ["id_ed25519", "legacy"])
    }

    @Test func parsesSSHGOutput() throws {
        let output = """
        user albert
        hostname 192.168.1.196
        port 22
        identityfile ~/.ssh/id_ed25519
        identityfile ~/.ssh/id_rsa
        batchmode no
        """
        let r = try #require(SSHConfigFile.parseResolved(output))
        #expect(r == ResolvedSSHHost(hostName: "192.168.1.196", user: "albert", port: "22",
                                     identityFiles: ["~/.ssh/id_ed25519", "~/.ssh/id_rsa"]))
        #expect(SSHConfigFile.parseResolved("user a\n") == nil)
    }

    @Test func abbreviatesHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(SSHConfigFile.abbreviatingHome(home + "/.ssh/id_rsa") == "~/.ssh/id_rsa")
        #expect(SSHConfigFile.abbreviatingHome(home) == "~")
        #expect(SSHConfigFile.abbreviatingHome("/etc/ssh/key") == "/etc/ssh/key")
        #expect(SSHConfigFile.abbreviatingHome(home + "other/key") == home + "other/key")
    }
}
