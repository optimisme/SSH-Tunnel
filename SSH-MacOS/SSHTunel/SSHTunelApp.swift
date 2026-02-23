//  SSHTunelApp.swift

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillCloseNote(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func windowWillCloseNote(_ note: Notification) {
        DispatchQueue.main.async {
            let regularVisibleWindows = NSApp.windows.filter { w in
                w.isVisible && w.styleMask.contains(.titled)
            }
            if regularVisibleWindows.isEmpty {
                NSApp.terminate(nil)
            }
        }
    }
}

@main
struct SSHTunelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store: SSHConfigStore

    init() {
        let s = SSHConfigStore()
        _store = StateObject(wrappedValue: s)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}
