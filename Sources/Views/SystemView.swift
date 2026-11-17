import SwiftUI
import LocalAuthentication

struct SystemView: View {
    @EnvironmentObject var client: HubClient
    @State private var showPowerCycleAlert = false
    @State private var showTerminal = false
    @State private var showDealLogs = false

    var body: some View {
        NavigationStack {
            List {
                // Connection & Tailscale
                Section("Verbindung (Tailscale & WLAN)") {
                    Picker("Route", selection: Binding(
                        get: { client.connectionMode },
                        set: { client.connectionMode = $0 }
                    )) {
                        ForEach(ConnectionMode.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledContent("Aktiver Pi-Host", value: "\(client.activePiHost) (\(client.activeRouteLabel))")
                    LabeledContent("PC-Zieladresse", value: client.resolvedPcHost)

                    NavigationLink("IP-Adressen anpassen") {
                        Form {
                            Section("Raspberry Pi 4") {
                                TextField("Tailscale IP", text: $client.piTailscaleIP).keyboardType(.numbersAndPunctuation)
                                TextField("WLAN IP", text: $client.piLanIP).keyboardType(.numbersAndPunctuation)
                            }
                            Section("Windows HomeServer PC") {
                                TextField("Tailscale IP", text: $client.pcTailscaleIP).keyboardType(.numbersAndPunctuation)
                                TextField("WLAN IP", text: $client.pcLanIP).keyboardType(.numbersAndPunctuation)
                            }
                        }
                        .navigationTitle("Host-Adressen")
                    }
                }

                // Raspberry Pi 4 Gateway Stats
                Section("Raspberry Pi 4 Gateway") {
                    if let pi = client.jellyStatus?.piStats {
                        LabeledContent("CPU-Temperatur", value: pi.tempC.map { String(format: "%.1f °C", $0) } ?? "--")
                        LabeledContent("CPU-Load (1m)", value: pi.load1m.map { String(format: "%.2f", $0) } ?? "--")
                        if let pct = pi.ramPct, let u = pi.ramUsedMb, let t = pi.ramTotalMb {
                            LabeledContent("RAM", value: "\(u) / \(t) MB (\(pct)%)")
                        }
                        LabeledContent("Uptime", value: pi.uptime ?? "--")
                    } else {
                        Text("Keine Pi-Telemetrie geladen").foregroundStyle(.secondary)
                    }
                }

                // SideStore Auto-Signing Server on Pi
                Section("SideStore Auto-Sign (Anisette v3)") {
                    HStack {
                        Label("Pi Anisette-Server (:6969)", systemImage: "signature")
                        Spacer()
                        Text(client.anisetteOnline ? "ONLINE" : "OFFLINE")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((client.anisetteOnline ? Color.green : Color.red).opacity(0.2), in: Capsule())
                            .foregroundStyle(client.anisetteOnline ? .green : .red)
                    }

                    Button {
                        UIPasteboard.general.string = client.anisetteURL
                        Haptics.success()
                        client.showToast("📋 Anisette-URL kopiert!")
                    } label: {
                        LabeledContent("Server-URL (kopieren)", value: client.anisetteURL)
                    }

                    Text("Trage diese URL in SideStore unter Einstellungen → Anisette Server (Custom) ein. Mit einer iOS-Kurzbefehl-Automation (nachts beim Laden: StosVPN → SideStore Refresh) signiert sich HomeHub alle 7 Tage vollautomatisch neu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // SmartLife Plug (Protected with Face ID!)
                Section("SmartLife Steckdose (Notfall)") {
                    let plugOn = client.jellyStatus?.plug?.state ?? true
                    HStack {
                        Label("230V Relais", systemImage: "powerplug.fill")
                        Spacer()
                        Text(plugOn ? "STROM AN" : "STROM AUS")
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((plugOn ? Color.green : Color.red).opacity(0.2), in: Capsule())
                            .foregroundStyle(plugOn ? .green : .red)
                    }

                    Button(role: .destructive) {
                        authenticateAndPromptPowerCycle()
                    } label: {
                        Label("Notfall Power-Cycle (Face ID geschützt)", systemImage: "faceid")
                    }
                }

                // Logs & Diagnostics
                Section("Logs & Diagnose") {
                    Button {
                        showTerminal = true
                    } label: {
                        Label("PC Power-Status & Logs", systemImage: "terminal")
                    }
                    Button {
                        Task {
                            await client.fetchDealLogs()
                            showDealLogs = true
                        }
                    } label: {
                        Label("Deal Radar Live-Logs", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }
            .navigationTitle("System")
            .refreshable {
                await client.resolveActiveHost()
                await client.refreshJelly()
                await client.checkAnisetteHealth()
            }
            .alert("⚠️ Notfall Power-Cycle ausführen?", isPresented: $showPowerCycleAlert) {
                Button("Abbrechen", role: .cancel) {}
                Button("Strom 5s trennen & neustarten", role: .destructive) {
                    Task { await client.sendJellyAction("/api/plug/powercycle", fallbackMsg: "Power-Cycle gestartet!") }
                }
            } message: {
                if client.jellyStatus?.pcOnline == true {
                    Text("ACHTUNG: Dein PC ist gerade ONLINE! Ein Power-Cycle trennt den Strom hart (wie Stecker ziehen) und kann Datenverlust verursachen. Nur bei komplettem Freeze nutzen!")
                } else {
                    Text("Die SmartLife-Steckdose wird für 5 Sekunden getrennt und danach automatisch wieder eingeschaltet.")
                }
            }
            .sheet(isPresented: $showTerminal) {
                NavigationStack {
                    ScrollView {
                        Text(client.jellyStatus?.terminalText ?? "Keine Daten")
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .background(Color.black)
                    .navigationTitle("PC Status & Power-Log")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { showTerminal = false } }
                    }
                }
            }
            .sheet(isPresented: $showDealLogs) {
                NavigationStack {
                    List(client.dealLogs) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            Text(entry.ts).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            Text(entry.msg).font(.caption.monospaced())
                        }
                    }
                    .navigationTitle("Deal Radar Logs")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { showDealLogs = false } }
                    }
                }
            }
        }
        .task {
            await client.checkAnisetteHealth()
        }
    }

    private func authenticateAndPromptPowerCycle() {
        Haptics.warning()
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Notfall Power-Cycle für SmartLife-Steckdose freigeben") { success, _ in
                Task { @MainActor in
                    if success {
                        showPowerCycleAlert = true
                    } else {
                        client.showToast("🔒 Face ID abgebrochen")
                    }
                }
            }
        } else {
            showPowerCycleAlert = true
        }
    }
}
