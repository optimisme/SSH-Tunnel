import Foundation
import Testing
@testable import SSHTunel

@MainActor
struct ControllerTests {
    private func controller(host: String = "host", user: String = "albert", port: String = "",
                            rules: [PortForwardRule]? = nil) -> SSHConnectionController {
        SSHConnectionController(snapshot: .init(
            host: host, user: user, sshPort: port, keyPath: "",
            forwardRules: rules ?? [PortForwardRule(name: "VNC", localPort: "5901", remoteHost: "localhost", remotePort: "5900")],
            autoReconnect: false))
    }

    @Test func fnvHashIsStable() {
        #expect(SSHConnectionController.stableShortHash("") == "cbf29ce484222325")
        #expect(SSHConnectionController.stableShortHash("a") == "af63dc4c8601ec8c")
    }

    /// Tunnels started by earlier versions must still be recognised: never change this format.
    @Test func controlSocketPathIsStable() {
        let c = controller(host: "192.168.1.196", port: "22",
                           rules: [PortForwardRule(name: "SSH", localPort: "4229", remoteHost: "localhost", remotePort: "22")])
        #expect(c.controlSocketPath.hasSuffix("/.ssh/tunnelctl_3b70b313b747b28a.sock"))

        let reordered = controller(rules: [
            PortForwardRule(name: "b", localPort: "2", remoteHost: "h", remotePort: "2"),
            PortForwardRule(name: "a", localPort: "1", remoteHost: "h", remotePort: "1"),
        ])
        reordered.moveForwardRule(from: 0, to: 1)
        let before = reordered.controlSocketPath
        reordered.moveForwardRule(from: 1, to: 0)
        #expect(reordered.controlSocketPath == before, "Rule order must not change the socket")
    }

    @Test func newConfigurationDefaults() {
        let c = SSHConnectionController(defaultLocalPort: "5905")
        #expect(c.keyPath == "~/.ssh/id_rsa")
        #expect(c.forwardRules.map(\.localPort) == ["5905"])
        #expect(c.forwardRules.first?.name == SSHConnectionController.ruleName(1))
        #expect(c.phase == .stopped)
    }

    @Test func validation() {
        #expect(controller().validationError() == nil)
        #expect(controller(user: "").validationError() == nil, "User may come from ~/.ssh/config")
        #expect(controller(host: " ").validationError() == .missingHost)
        #expect(controller(port: "abc").validationError() == .invalidSSHPort)
        #expect(controller(port: "0").validationError() == .invalidSSHPort)
        #expect(controller(port: "70000").validationError() == .invalidSSHPort)
        #expect(controller(rules: []).validationError() == .noRules)
        #expect(controller(rules: [PortForwardRule(name: "x", localPort: "0", remoteHost: "h", remotePort: "1")])
            .validationError() == .invalidPorts(rule: "x"))
        #expect(controller(rules: [PortForwardRule(name: "x", localPort: "1", remoteHost: " ", remotePort: "1")])
            .validationError() == .missingRemoteHost(rule: "x"))
        #expect(controller(rules: [
            PortForwardRule(name: "a", localPort: "80", remoteHost: "h", remotePort: "1"),
            PortForwardRule(name: "b", localPort: " 80", remoteHost: "h", remotePort: "2"),
        ]).validationError() == .duplicateLocalPort(80))
    }

    @Test func issuesHaveMessages() {
        let issues: [TunnelIssue] = [.missingHost, .invalidSSHPort, .noRules, .invalidPorts(rule: "r"),
                                     .missingRemoteHost(rule: "r"), .duplicateLocalPort(1), .hostKeyChanged,
                                     .localPortInUse("1"), .authentication, .sshConfiguration, .sshExited(255),
                                     .connectionLost, .cannotRunSSH]
        for issue in issues { #expect(!issue.message.isEmpty) }
        #expect(TunnelIssue.sshExited(255).message.contains("255"))
        #expect(TunnelIssue.invalidPorts(rule: "VNC").message.contains("VNC"))
    }

    @Test func addRuleSuggestsFreePortAndName() {
        let c = controller(rules: [PortForwardRule(name: SSHConnectionController.ruleName(1), localPort: "5901",
                                                   remoteHost: "localhost", remotePort: "5900")])
        c.addForwardRule()
        #expect(c.forwardRules.count == 2)
        #expect(c.forwardRules[1].localPort == "5902")
        #expect(c.forwardRules[1].name == SSHConnectionController.ruleName(2))
    }

    @Test func moveAndRemoveRules() {
        let c = controller(rules: ["a", "b", "c"].enumerated().map {
            PortForwardRule(name: $1, localPort: "\(1000 + $0)", remoteHost: "h", remotePort: "1")
        })
        c.moveForwardRule(from: 0, to: 2)
        #expect(c.forwardRules.map(\.name) == ["b", "c", "a"])
        c.moveForwardRule(from: 2, to: -5)
        #expect(c.forwardRules.map(\.name) == ["a", "b", "c"])
        c.moveForwardRule(from: 7, to: 0)
        #expect(c.forwardRules.map(\.name) == ["a", "b", "c"])

        c.removeForwardRule(id: c.forwardRules[1].id)
        #expect(c.forwardRules.map(\.name) == ["a", "c"])
        c.removeForwardRule(id: c.forwardRules[0].id)
        c.removeForwardRule(id: c.forwardRules[0].id)
        #expect(c.forwardRules.count == 1, "The last rule can't be removed")
    }

    @Test func snapshotRoundTrip() {
        let c = controller(host: "h", user: "u", port: "2222")
        c.keyPath = "~/.ssh/k"
        c.autoReconnect = true
        let copy = SSHConnectionController(snapshot: c.snapshot())
        #expect(copy.host == "h" && copy.user == "u" && copy.sshPort == "2222")
        #expect(copy.keyPath == "~/.ssh/k" && copy.autoReconnect)
        #expect(copy.forwardRules == c.forwardRules)
    }
}
