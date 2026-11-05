//  ContentView.swift

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: SSHConfigStore
    @State private var pendingDeletionID: UUID?

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedID) {
                Section("SSH Configurations") {
                    ForEach(store.configurations) { cfg in
                        ConfigRow(configuration: cfg, connection: cfg.connection)
                            .tag(cfg.id)
                            .contextMenu {
                                Button("Duplicate") { store.duplicate(id: cfg.id) }
                                Divider()
                                Button("Delete…", role: .destructive) { pendingDeletionID = cfg.id }
                            }
                    }
                    .onMove(perform: store.move)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 220, max: 340)
            .onDeleteCommand { pendingDeletionID = store.selectedID }
            .toolbar {
                ToolbarItem {
                    Button(action: store.addConfiguration) {
                        Label("Add Configuration", systemImage: "plus")
                    }
                    .help("Add Configuration")
                }
            }
        } detail: {
            if let cfg = store.selectedConfiguration {
                ConnectionDetailView(configuration: cfg, connection: cfg.connection)
                    .id(cfg.id)
                    .toolbar {
                        ToolbarItem {
                            Button(role: .destructive) {
                                pendingDeletionID = cfg.id
                            } label: {
                                Label("Delete Configuration", systemImage: "trash")
                            }
                            .help("Delete Configuration")
                        }
                    }
            } else {
                ContentUnavailableView(
                    "No Configuration Selected",
                    systemImage: "network",
                    description: Text("Select a configuration or add a new one.")
                )
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { pendingDeletionID != nil },
                set: { if !$0 { pendingDeletionID = nil } }
            ),
            presenting: pendingDeletionID
        ) { id in
            Button("Delete", role: .destructive) { store.remove(id: id) }
        } message: { _ in
            Text("If the tunnel is active, it will be stopped.")
        }
    }

    private var deletionTitle: Text {
        let name = store.configurations.first { $0.id == pendingDeletionID }?.name ?? ""
        return Text("Delete “\(name)”?")
    }
}

// MARK: - Detail

private struct ConnectionDetailView: View {
    @ObservedObject var configuration: SSHConfiguration
    @ObservedObject var connection: SSHConnectionController

    @State private var hostAliases: [String] = []
    @State private var privateKeys: [String] = []
    @State private var resolvedHost: ResolvedSSHHost?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Configuration Name")
                    .fontWeight(.bold)
                TextField("Configuration Name", text: $configuration.name, prompt: Text("Name"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()

                GroupBox {
                    sshSection
                        .textFieldStyle(.roundedBorder)
                } label: {
                    Text("SSH Connection").fontWeight(.bold)
                }
                .disabled(connection.isRunning)

                GroupBox {
                    ForwardRulesEditor(connection: connection)
                        .textFieldStyle(.roundedBorder)
                } label: {
                    Text("Port Forwarding Rules").fontWeight(.bold)
                }
                .disabled(connection.isRunning)

                Toggle("Reconnect automatically if the connection drops (and after waking from sleep)",
                       isOn: $connection.autoReconnect)

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        ScrollView {
                            Text(connection.logText.isEmpty ? "—" : connection.logText)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .padding(.vertical, 6)
                        }
                        .defaultScrollAnchor(.bottom)
                        .frame(height: 100)

                        HStack {
                            Button("Clear") { connection.clearLog() }
                            Spacer()
                        }
                    }
                } label: {
                    Text("ssh Output").fontWeight(.bold)
                }

                HStack(spacing: 10) {
                    Button("Connect") { connection.start() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(connection.isRunning)
                    Button("Disconnect") { connection.stop() }
                        .disabled(!connection.isRunning || connection.phase == .stopping)
                    Button("Refresh") { connection.refresh() }

                    Spacer()

                    HStack(spacing: 6) {
                        Circle().fill(connection.statusColor).frame(width: 10, height: 10)
                        Text(connection.statusLabel).foregroundStyle(connection.statusColor)
                        if !connection.statusDetail.isEmpty {
                            Text(connection.statusDetail)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(configuration.name)
        .navigationSubtitle(connection.statusLabel)
        .onAppear { connection.refresh() }
        .task {
            let found = await ProcessRunner.background {
                (SSHConfigFile.hostAliases(), SSHConfigFile.privateKeys())
            }
            hostAliases = found.0
            privateKeys = found.1
        }
        .task(id: "\(connection.host)|\(hostAliases.count)") {
            let host = connection.host.trimmed
            guard hostAliases.contains(host) else {
                resolvedHost = nil
                return
            }
            resolvedHost = await ProcessRunner.background { SSHConfigFile.resolve(host: host) }
        }
    }

    private var sshSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                fieldLabel("Host")
                TextField("Host", text: $connection.host, prompt: Text("Host name, IP or ~/.ssh/config alias"))
                    .labelsHidden()
                hostAliasMenu
            }
            if let resolved = resolvedHost {
                HStack {
                    Color.clear.frame(width: 70, height: 1)
                    Text("From ~/.ssh/config: \(resolvedSummary(resolved))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            HStack {
                fieldLabel("User")
                TextField("User", text: $connection.user, prompt: Text(userPrompt))
                    .labelsHidden()
            }
            HStack {
                fieldLabel("Port")
                TextField("Port", text: $connection.sshPort, prompt: Text(verbatim: "22"))
                    .labelsHidden()
                    .frame(width: 80)
            }
            HStack {
                fieldLabel("Key")
                TextField("Key", text: $connection.keyPath, prompt: Text("Use ssh-agent"))
                    .labelsHidden()
                keyMenu
            }
        }
    }

    private var userPrompt: LocalizedStringKey {
        resolvedHost.map { "From ~/.ssh/config (\($0.user))" } ?? "Default (\(NSUserName()))"
    }

    private func resolvedSummary(_ r: ResolvedSSHHost) -> String {
        let port = r.port.isEmpty || r.port == "22" ? "" : ":\(r.port)"
        return "\(r.user)@\(r.hostName)\(port)"
    }

    private var hostAliasMenu: some View {
        Menu {
            if hostAliases.isEmpty {
                Text("No hosts in ~/.ssh/config")
            } else {
                ForEach(hostAliases, id: \.self) { alias in
                    Button(alias) { connection.host = alias }
                }
            }
        } label: {
            Image(systemName: "list.bullet")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Hosts from ~/.ssh/config")
    }

    private var keyMenu: some View {
        Menu {
            Button("Use ssh-agent and ~/.ssh/config") { connection.keyPath = "" }
            if !privateKeys.isEmpty {
                Divider()
                ForEach(privateKeys, id: \.self) { key in
                    Button(key) { connection.keyPath = key }
                }
            }
            Divider()
            Button("Choose…") { chooseKeyFile() }
        } label: {
            Image(systemName: "key")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose a private key")
    }

    private func chooseKeyFile() {
        let panel = NSOpenPanel()
        panel.message = String(localized: "Choose the private key for this connection.", comment: "Open panel message")
        panel.prompt = String(localized: "Choose", comment: "Open panel button")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.treatsFilePackagesAsDirectories = true
        let current = (connection.keyPath.trimmed as NSString).expandingTildeInPath
        if !current.isEmpty, FileManager.default.fileExists(atPath: current) {
            panel.directoryURL = URL(fileURLWithPath: current).deletingLastPathComponent()
        } else {
            panel.directoryURL = SSHConfigFile.sshDirectory
        }
        if panel.runModal() == .OK, let url = panel.url {
            connection.keyPath = SSHConfigFile.abbreviatingHome(url.path)
        }
    }

    private func fieldLabel(_ title: LocalizedStringKey) -> some View {
        Text(title).frame(width: 70, alignment: .leading)
    }
}

// MARK: - Forward rules

private struct ForwardRulesEditor: View {
    @ObservedObject var connection: SSHConnectionController

    @State private var draggedID: UUID?
    @State private var dragOffset: CGFloat = 0

    private let rowHeight: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 0) {
                ForEach($connection.forwardRules) { $rule in
                    row($rule)
                        .frame(height: rowHeight)
                        .background {
                            if draggedID == rule.id {
                                RoundedRectangle(cornerRadius: 6).fill(.background).shadow(radius: 3)
                            }
                        }
                        .offset(y: offset(for: rule.id))
                        .zIndex(draggedID == rule.id ? 1 : 0)
                        .animation(draggedID == rule.id ? nil : .easeInOut(duration: 0.15), value: targetIndex)
                }
            }
            .coordinateSpace(name: "rules")

            HStack {
                Button {
                    connection.addForwardRule()
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                Spacer()
            }
        }
    }

    private func row(_ rule: Binding<PortForwardRule>) -> some View {
        let id = rule.wrappedValue.id
        let canMove = connection.forwardRules.count > 1
        return HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 18, height: rowHeight)
                .contentShape(Rectangle())
                .pointerStyle(canMove ? .grabIdle : nil)
                .gesture(dragGesture(for: id), including: canMove ? .all : .none)
                .contextMenu {
                    Button("Move Up") { move(id, by: -1) }.disabled(index(of: id) == 0)
                    Button("Move Down") { move(id, by: 1) }
                        .disabled(index(of: id) == connection.forwardRules.count - 1)
                }
                .accessibilityLabel("Reorder")
                .accessibilityAction(named: "Move Up") { move(id, by: -1) }
                .accessibilityAction(named: "Move Down") { move(id, by: 1) }
                .help("Drag to reorder")

            Text("Name").fixedSize()
            TextField("Name", text: rule.name).labelsHidden().frame(width: 130)
            Text("Local").fixedSize()
            TextField("Local port", text: rule.localPort, prompt: Text(verbatim: "5901"))
                .labelsHidden().frame(width: 70)
            Text(verbatim: "→")
            TextField("Remote host", text: rule.remoteHost, prompt: Text(verbatim: "localhost"))
                .labelsHidden()
            TextField("Remote port", text: rule.remotePort, prompt: Text(verbatim: "5900"))
                .labelsHidden().frame(width: 70)

            Button(role: .destructive) {
                connection.removeForwardRule(id: id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete Rule")
            .accessibilityLabel("Delete Rule")
            .disabled(!canMove)
        }
    }

    // MARK: Dragging

    private func index(of id: UUID) -> Int? {
        connection.forwardRules.firstIndex { $0.id == id }
    }

    private var targetIndex: Int? {
        guard let id = draggedID, let from = index(of: id) else { return nil }
        let steps = Int((dragOffset / rowHeight).rounded())
        return min(max(from + steps, 0), connection.forwardRules.count - 1)
    }

    private func offset(for id: UUID) -> CGFloat {
        guard let dragged = draggedID, let from = index(of: dragged),
              let to = targetIndex, let i = index(of: id) else { return 0 }
        if id == dragged { return dragOffset }
        if from < to, i > from, i <= to { return -rowHeight }
        if to < from, i >= to, i < from { return rowHeight }
        return 0
    }

    private func dragGesture(for id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("rules"))
            .onChanged { value in
                draggedID = id
                dragOffset = value.translation.height
            }
            .onEnded { _ in
                let from = index(of: id)
                let to = targetIndex
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    if let from, let to { connection.moveForwardRule(from: from, to: to) }
                    draggedID = nil
                    dragOffset = 0
                }
            }
    }

    private func move(_ id: UUID, by delta: Int) {
        guard let i = index(of: id) else { return }
        connection.moveForwardRule(from: i, to: i + delta)
    }
}

// MARK: - Sidebar row

private struct ConfigRow: View {
    @ObservedObject var configuration: SSHConfiguration
    @ObservedObject var connection: SSHConnectionController

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connection.statusColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(configuration.name)
                .lineLimit(1)
        }
        .help(connection.statusDetail.isEmpty ? connection.statusLabel : "\(connection.statusLabel): \(connection.statusDetail)")
        .accessibilityElement(children: .combine)
        .accessibilityValue(connection.statusLabel)
    }
}
