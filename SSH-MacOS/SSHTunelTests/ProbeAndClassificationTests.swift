import Foundation
import Testing
@testable import SSHTunel

struct FailureClassificationTests {
    @Test(arguments: [
        ("Host key verification failed.", SSHConnectionController.FailureKind.hostKeyChanged),
        ("@ WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED! @", .hostKeyChanged),
        ("bind [127.0.0.1]:5901: Address already in use", .addressInUse),
        ("channel_setup_fwd_listener_tcpip: cannot listen to port: 5901", .addressInUse),
        ("albert@host: Permission denied (publickey).", .authOrKey),
        ("Warning: Identity file /Users/a/.ssh/nope not accessible: No such file or directory.", .authOrKey),
        ("command-line line 0: Bad configuration option: foo", .config),
        ("Connection timed out during banner exchange", .transient),
        ("ssh: connect to host 192.168.1.195 port 22: No route to host", .transient),
        ("ssh: Could not resolve hostname nowhere: nodename nor servname provided", .transient),
        ("something unexpected", .other),
    ])
    func classifies(_ log: String, _ expected: SSHConnectionController.FailureKind) {
        #expect(SSHConnectionController.classifyFailure(log) == expected)
    }

    @Test func hostKeyWinsOverPermissionDenied() {
        let log = "Host key verification failed.\nPermission denied"
        #expect(SSHConnectionController.classifyFailure(log) == .hostKeyChanged)
    }
}

struct TunnelProbeMatchTests {
    private func spec(target: String = "albert@host", port: String = "", forwards: [String] = ["5901:localhost:5900"]) -> TunnelSpec {
        TunnelSpec(target: target, sshPort: port, localPorts: [5901], forwards: forwards, controlSocketPath: "/tmp/x.sock")
    }

    @Test func matchesOwnCommandLine() {
        let cmd = "/usr/bin/ssh -N -T -i /Users/a/.ssh/id_rsa -L 5901:localhost:5900 -o ExitOnForwardFailure=yes albert@host"
        #expect(TunnelProbe.matches(commandLine: cmd, spec: spec()))
    }

    @Test func matchesJoinedFlagValue() {
        let cmd = "ssh -N -L5901:localhost:5900 -p2222 albert@host"
        #expect(TunnelProbe.matches(commandLine: cmd, spec: spec(port: "2222")))
    }

    @Test func portMustMatchExactly() {
        let cmd = "/usr/bin/ssh -N -p 2222 -L 5901:localhost:5900 albert@host"
        #expect(!TunnelProbe.matches(commandLine: cmd, spec: spec(port: "22")))
        #expect(!TunnelProbe.matches(commandLine: cmd, spec: spec(port: "222")))
        #expect(TunnelProbe.matches(commandLine: cmd, spec: spec(port: "2222")))
    }

    @Test func rejectsOtherTargetsForwardsAndPrograms() {
        #expect(!TunnelProbe.matches(commandLine: "/usr/bin/ssh -L 5901:localhost:5900 other@host", spec: spec()))
        #expect(!TunnelProbe.matches(commandLine: "/usr/bin/ssh -L 5901:localhost:5999 albert@host", spec: spec()))
        #expect(!TunnelProbe.matches(commandLine: "/usr/bin/autossh -L 5901:localhost:5900 albert@host", spec: spec()))
        #expect(!TunnelProbe.matches(commandLine: "", spec: spec()))
    }

    @Test func matchesBareAliasTarget() {
        let cmd = "/usr/bin/ssh -N -L 5901:localhost:5900 bsd"
        #expect(TunnelProbe.matches(commandLine: cmd, spec: spec(target: "bsd")))
    }
}

struct SMBTests {
    @Test func homeURLEncodesUser() throws {
        let url = try #require(SMB.homeURL(user: " joan pere ", localPort: "4445"))
        #expect(url.absoluteString == "smb://joan%20pere@localhost:4445/joan%20pere")
        let target = try #require(SMB.target(from: url))
        #expect(target == SMBTarget(user: "joan pere", host: "localhost", port: 4445, path: "joan%20pere"))
    }

    @Test func homeURLRequiresUserAndPort() {
        #expect(SMB.homeURL(user: "", localPort: "445") == nil)
        #expect(SMB.homeURL(user: "a", localPort: "x") == nil)
    }

    @Test func remountMatching() throws {
        let targets: Set = [SMBTarget(user: "albert", host: "localhost", port: 4445, path: "albert")]
        #expect(SMB.isMatchingRemountURL(try #require(URL(string: "smb://albert@localhost:4445/albert")), targets: targets))
        #expect(SMB.isMatchingRemountURL(try #require(URL(string: "smb://albert@LOCALHOST:4445/albert/")), targets: targets))
        #expect(!SMB.isMatchingRemountURL(try #require(URL(string: "smb://albert@localhost:4446/albert")), targets: targets))
        #expect(!SMB.isMatchingRemountURL(try #require(URL(string: "smb://albert@localhost/albert")), targets: targets))
        #expect(!SMB.isMatchingRemountURL(try #require(URL(string: "afp://albert@localhost:4445/albert")), targets: targets))

        let defaultPort: Set = [SMBTarget(user: "albert", host: "nas", port: 445, path: "home")]
        #expect(SMB.isMatchingRemountURL(try #require(URL(string: "smb://albert@nas/home")), targets: defaultPort))
    }
}
