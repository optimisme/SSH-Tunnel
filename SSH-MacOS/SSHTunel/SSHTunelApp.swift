//  SSHTunelApp.swift

import SwiftUI
import AppKit

/// What to do with open tunnels when the app quits.
enum QuitBehavior: String, CaseIterable, Identifiable {
    case ask
    case closeTunnels
    case keepTunnels

    var id: Self { self }

    static let defaultsKey = "quitBehavior"

    static var current: QuitBehavior {
        get { UserDefaults.standard.string(forKey: defaultsKey).flatMap(QuitBehavior.init(rawValue:)) ?? .ask }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey) }
    }

    var title: LocalizedStringKey {
        switch self {
        case .ask: return "Ask"
        case .closeTunnels: return "Close the tunnels"
        case .keepTunnels: return "Keep the tunnels running"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store: SSHConfigStore

    override init() {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil {
            // Hosting unit tests: never touch the user's configurations or tunnels.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("SSHTunel-host-\(UUID().uuidString)")
                .appendingPathComponent("configs.json")
            store = SSHConfigStore(saveURL: url, observeSystem: false)
        } else {
            store = SSHConfigStore()
        }
        super.init()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let running = store.runningConfigurations.count
        guard running > 0 else { return .terminateNow }

        var behavior = QuitBehavior.current
        if behavior == .ask {
            guard let choice = askAboutOpenTunnels(count: running) else { return .terminateCancel }
            behavior = choice
        }
        guard behavior == .closeTunnels else { return .terminateNow }

        Task {
            await store.stopAll()
            store.saveNow()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Returns nil when the user cancels the quit.
    private func askAboutOpenTunnels(count: Int) -> QuitBehavior? {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Close \(count) open tunnels before quitting?",
                                   comment: "Quit alert title; plural by count")
        alert.informativeText = String(localized: "Tunnels you keep running stay available after SSH Túnel quits, and the app picks them up again the next time it opens.",
                                       comment: "Quit alert message")
        alert.addButton(withTitle: String(localized: "Close Tunnels", comment: "Quit alert button"))
        alert.addButton(withTitle: String(localized: "Keep Running", comment: "Quit alert button"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Quit alert button"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Don’t ask again", comment: "Quit alert checkbox; the choice can be changed in Settings")

        let choice: QuitBehavior
        switch alert.runModal() {
        case .alertFirstButtonReturn: choice = .closeTunnels
        case .alertSecondButtonReturn: choice = .keepTunnels
        default: return nil
        }
        if alert.suppressionButton?.state == .on {
            QuitBehavior.current = choice
        }
        return choice
    }
}

@main
struct SSHTunelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("SSH Túnel", id: "main") {
            ContentView()
                .environmentObject(appDelegate.store)
        }
        .defaultSize(width: 900, height: 640)

        Settings {
            SettingsView()
        }
    }
}

private struct SettingsView: View {
    @AppStorage(QuitBehavior.defaultsKey) private var quitBehavior: QuitBehavior = .ask

    var body: some View {
        Form {
            Picker("When quitting with open tunnels:", selection: $quitBehavior) {
                ForEach(QuitBehavior.allCases) { behavior in
                    Text(behavior.title).tag(behavior)
                }
            }
            .pickerStyle(.radioGroup)
        }
        .padding(20)
        .frame(width: 420)
    }
}
