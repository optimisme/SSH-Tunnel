//  ContentView.swift

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var store: SSHConfigStore
    @State private var sidebarWidth: CGFloat = 220
    @State private var sidebarDragOrigin: CGFloat?
    @State private var confirmDelete = false
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
                    .onMove(perform: store.move)
                }
                .frame(maxWidth: .infinity)

                HStack {
                    Button(action: store.addConfiguration) {
                        Text("+ Afegir")
                    }
                    .help("Afegir configuració")

                    Spacer()

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
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
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
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
                    .id(cfg.id)
                    .frame(minWidth: 520)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
            } else {
                VStack {
                    Text("Selecciona o crea una configuració").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .controlSize(.small)
        .font(.system(size: 11))
        .frame(minWidth: 700, minHeight: 420)
        .confirmationDialog(
            "Eliminar «\(store.selectedConfiguration?.name ?? "")»?",
            isPresented: $confirmDelete
        ) {
            Button("Eliminar", role: .destructive, action: store.removeSelected)
        } message: {
            Text("Si el túnel està actiu, s'aturarà.")
        }
    }
}

private struct ConnectionDetailView: View {
    @ObservedObject var configuration: SSHConfiguration
    @ObservedObject var connection: SSHConnectionController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nom configuració")
                    .fontWeight(.bold)
                TextField("Nom de la configuració", text: $configuration.name)
                    .textFieldStyle(.roundedBorder)

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        row("Host", $connection.host)
                        row("Usuari", $connection.user)
                        row("Port", $connection.sshPort, width: 80, prompt: "22")
                        row("Clau", $connection.keyPath, prompt: "~/.ssh/id_ed25519")
                    }
                    .textFieldStyle(.roundedBorder)
                } label: {
                    Text("Connexió SSH")
                        .font(.body)
                        .fontWeight(.bold)
                }
                .disabled(connection.isRunning)

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
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
                                .disabled(connection.forwardRules.count == 1)
                            }
                        }

                        HStack {
                            Button {
                                connection.addForwardRule()
                            } label: {
                                Label("Afegir regla", systemImage: "plus")
                            }
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

                Toggle("Reconnectar automàticament si es perd la connexió (i en despertar l'ordinador)", isOn: $connection.autoReconnect)

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
                        .frame(height: 90)

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
                    Button("Desactivar") { connection.stop() }
                        .disabled(!connection.isRunning || connection.phase == .stopping)
                    Button("Refrescar") { connection.refresh() }

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
            .padding(10)
        }
        .onAppear { connection.refresh() }
    }

    private func row(_ label: String, _ binding: Binding<String>, width: CGFloat? = nil, prompt: String = "") -> some View {
        HStack {
            Text(label).frame(width: 70, alignment: .leading)
            TextField("", text: binding, prompt: prompt.isEmpty ? nil : Text(prompt)).frame(width: width)
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
        .help(connection.statusDetail.isEmpty ? connection.statusLabel : "\(connection.statusLabel): \(connection.statusDetail)")
    }
}
