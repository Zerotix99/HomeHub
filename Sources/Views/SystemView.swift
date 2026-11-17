import SwiftUI
import LocalAuthentication

struct SystemView: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.openURL) private var openURL

    @State private var showPowerCycleAlert = false
    @State private var showTerminal = false
    @State private var showDealLogs = false
    @State private var showIPEditor = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    PiGatewayBar()

                    appUpdateAndSideStoreCard

                    sideJITServerCard

                    networkRouteCard

                    piGatewayAndAnisetteCard

                    diagnosticsAndEmergencyCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .background(HubTheme.bg.ignoresSafeArea())
            .navigationTitle("System & Tailscale JIT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        Task {
                            await client.resolveActiveHost()
                            await client.refreshJelly()
                            await client.checkAnisetteHealth()
                            await client.checkSideJIT()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title3)
                            .foregroundStyle(HubTheme.sky)
                    }
                }
            }
            .refreshable {
                await client.resolveActiveHost()
                await client.refreshJelly()
                await client.checkAnisetteHealth()
                await client.checkSideJIT()
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
            .sheet(isPresented: $showIPEditor) {
                ipEditorSheet
            }
            .sheet(isPresented: $showTerminal) {
                NavigationStack {
                    ScrollView {
                        Text(client.jellyStatus?.terminalText ?? "Keine Daten")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.green)
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
                    .navigationTitle("Deal Radar Live-Logs")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Fertig") { showDealLogs = false } }
                    }
                }
            }
        }
        .task {
            await client.checkAnisetteHealth()
            await client.checkSideJIT()
        }
    }

    // MARK: - 1. App Update & SideStore Card

    private var appUpdateAndSideStoreCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(symbol: "iphone.and.arrow.forward", colors: [HubTheme.indigo, HubTheme.purple], size: 38, iconSize: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SideStore & Remote App-Update")
                        .font(.system(size: 15, weight: .heavy))
                    Text("Unterwegs per Tailscale refreshen & aktualisieren")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadgePill(text: "v2.0", active: true, activeColor: HubTheme.sky)
            }

            // 1-Tap SideStore Install / Update
            Button {
                Haptics.medium()
                let encoded = client.githubLatestIPAURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? client.githubLatestIPAURL
                if let url = URL(string: "sidestore://install?url=\(encoded)") {
                    openURL(url)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.app.fill")
                        .font(.title3.bold())
                    VStack(alignment: .leading, spacing: 1) {
                        Text("HomeHub via SideStore aktualisieren")
                            .font(.system(size: 13.5, weight: .heavy))
                        Text("Lädt neueste IPA von GitHub direkt in SideStore")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                    Image(systemName: "arrow.up.forward.app.fill")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(LinearGradient(colors: [HubTheme.indigo, HubTheme.purple], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Button {
                    Haptics.light()
                    if let url = URL(string: "sidestore://") {
                        openURL(url)
                    }
                } label: {
                    Label("SideStore öffnen", systemImage: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(HubTheme.cardElevated, in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(HubTheme.border, lineWidth: 1))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.light()
                    if let url = URL(string: client.githubLatestIPAURL) {
                        openURL(url)
                    }
                } label: {
                    Label("IPA in Safari laden", systemImage: "safari.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(HubTheme.cardElevated, in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(HubTheme.border, lineWidth: 1))
                        .foregroundStyle(HubTheme.sky)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .hubCard(cornerRadius: 18, highlight: HubTheme.indigo)
    }

    // MARK: - 2. SideJITServer Card (:9191)

    private var sideJITServerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(symbol: "cpu.fill", colors: [HubTheme.emerald, HubTheme.sky], size: 38, iconSize: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pi 4 SideJITServer (:9191)")
                        .font(.system(size: 15, weight: .heavy))
                    Text(client.sideJITOnline ? "Aktiv • \(client.sideJITVersion)" : "Verbinde mit Port 9191…")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadgePill(text: client.sideJITOnline ? "ONLINE" : "OFFLINE", active: client.sideJITOnline)
            }

            // Copyable Server Address for SideStore Settings -> SideJITServer
            Button {
                let tsURL = "http://\(client.piTailscaleIP):9191"
                UIPasteboard.general.string = tsURL
                Haptics.success()
                client.showToast("📋 \(tsURL) kopiert!")
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SERVER-ADRESSE FÜR SIDESTORE (TIPPEN ZUM KOPIEREN)")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(.secondary)
                        Text("http://\(client.piTailscaleIP):9191")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(HubTheme.sky)
                    }
                    Spacer()
                    Image(systemName: "doc.on.doc.fill")
                        .foregroundStyle(HubTheme.sky)
                }
                .padding(10)
                .background(HubTheme.bg.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(HubTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            // Refresh / Mount Developer Disk Image Button
            Button {
                Task { await client.refreshSideJITDevices() }
            } label: {
                HStack(spacing: 8) {
                    if client.isRefreshingJIT {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles.tv.fill")
                    }
                    Text(client.isRefreshingJIT ? "Suche iPhone & mounte Developer Image…" : "iPhone verbinden & JIT-Apps laden (/re/)")
                        .font(.system(size: 12.5, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(LinearGradient(colors: [HubTheme.emerald, .teal], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(client.isRefreshingJIT)

            if !client.sideJITApps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ERKANNTE APPS AUF DEINEM IPHONE:")
                        .font(.system(size: 9.5, weight: .heavy))
                        .foregroundStyle(.secondary)

                    ForEach(client.sideJITApps) { app in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.name)
                                    .font(.system(size: 13, weight: .bold))
                                Text(app.bundle)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { await client.enableJIT(for: app) }
                            } label: {
                                Label("JIT", systemImage: "bolt.fill")
                                    .font(.system(size: 11.5, weight: .heavy))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(HubTheme.amber, in: Capsule())
                                    .foregroundStyle(.black)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(9)
                        .background(HubTheme.bg.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            } else {
                Text("💡 Tipp: Trage `http://\(client.piTailscaleIP):9191` in SideStore unter Settings → SideJITServer ein, um in SideStore per Long-Press auf eine App „Enable JIT“ zu nutzen.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .hubCard(cornerRadius: 18, highlight: client.sideJITOnline ? HubTheme.emerald : nil)
    }

    // MARK: - 3. Tailscale & Network Route Card

    private var networkRouteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(symbol: "network", colors: [HubTheme.sky, HubTheme.indigo], size: 38, iconSize: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tailscale & Netzwerk-Routing")
                        .font(.system(size: 15, weight: .heavy))
                    Text("Aktiv: \(client.activePiHost) (\(client.activeRouteLabel))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(HubTheme.sky)
                }
                Spacer()
                Button {
                    showIPEditor = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.subheadline.bold())
                        .padding(8)
                        .background(HubTheme.cardElevated, in: Circle())
                        .foregroundStyle(HubTheme.sky)
                }
                .buttonStyle(.plain)
            }

            Picker("Route", selection: Binding(
                get: { client.connectionMode },
                set: { client.connectionMode = $0 }
            )) {
                ForEach(ConnectionMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                GlowChip(text: "Pi: \(client.activePiHost)", dotColor: HubTheme.emerald, icon: "cpu")
                GlowChip(text: "PC: \(client.resolvedPcHost)", dotColor: HubTheme.sky, icon: "desktopcomputer")
                GlowChip(text: "Subnetz: 10.7.0.1", dotColor: HubTheme.purple, icon: "lock.shield")
            }
        }
        .padding(14)
        .hubCard(cornerRadius: 18)
    }

    // MARK: - 4. Pi 4 Telemetry & Anisette Card

    private var piGatewayAndAnisetteCard: some View {
        let pi = client.jellyStatus?.piStats
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(symbol: "server.rack", colors: [HubTheme.emerald, .teal], size: 38, iconSize: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Raspberry Pi 4 & Anisette v3")
                        .font(.system(size: 15, weight: .heavy))
                    Text("24/7 HomeServer Gateway & Apple Signierung")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadgePill(text: client.anisetteOnline ? "ANISETTE OK" : "OFFLINE", active: client.anisetteOnline)
            }

            HStack(spacing: 8) {
                piStatBox(label: "CPU TEMP", val: pi?.tempC.map { String(format: "%.1f°C", $0) } ?? "--", color: HubTheme.emerald)
                piStatBox(label: "LOAD (1M)", val: pi?.load1m.map { String(format: "%.2f", $0) } ?? "--", color: HubTheme.sky)
                piStatBox(label: "RAM", val: pi?.ramPct.map { "\($0)%" } ?? "--", color: HubTheme.purple)
                piStatBox(label: "UPTIME", val: pi?.uptime ?? "--", color: HubTheme.amber)
            }

            Button {
                UIPasteboard.general.string = client.anisetteURL
                Haptics.success()
                client.showToast("📋 Anisette-URL (\(client.anisetteURL)) kopiert!")
            } label: {
                HStack {
                    Image(systemName: "signature")
                        .foregroundStyle(HubTheme.emerald)
                    Text("Anisette v3: \(client.anisetteURL)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Kopieren")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(HubTheme.sky)
                }
                .padding(9)
                .background(HubTheme.bg.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .hubCard(cornerRadius: 18)
    }

    // MARK: - 5. Diagnostics & Face ID Emergency Plug

    private var diagnosticsAndEmergencyCard: some View {
        let plugOn = client.jellyStatus?.plug?.state ?? true
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(symbol: "wrench.and.screwdriver.fill", colors: [HubTheme.amber, HubTheme.rose], size: 38, iconSize: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Diagnose & Notfall-Steuerung")
                        .font(.system(size: 15, weight: .heavy))
                    Text("Live-Logs & SmartLife 230V Hardware-Reset")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadgePill(text: plugOn ? "230V AN" : "230V AUS", active: plugOn)
            }

            HStack(spacing: 8) {
                Button {
                    showTerminal = true
                } label: {
                    Label("PC Power-Log", systemImage: "terminal.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(HubTheme.cardElevated, in: RoundedRectangle(cornerRadius: 11))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        await client.fetchDealLogs()
                        showDealLogs = true
                    }
                } label: {
                    Label("Radar-Logs", systemImage: "doc.text.magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(HubTheme.cardElevated, in: RoundedRectangle(cornerRadius: 11))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Button {
                authenticateAndPromptPowerCycle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "faceid")
                        .font(.subheadline.bold())
                    Text("Notfall Power-Cycle (SmartLife 5s Reset)")
                        .font(.system(size: 12.5, weight: .bold))
                    Spacer()
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(HubTheme.rose.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(HubTheme.rose.opacity(0.45), lineWidth: 1))
                .foregroundStyle(HubTheme.rose)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .hubCard(cornerRadius: 18)
    }

    private func piStatBox(label: String, val: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 8.5, weight: .heavy)).foregroundStyle(.secondary)
            Text(val).font(.system(size: 12.5, weight: .heavy)).foregroundStyle(color).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(HubTheme.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private var ipEditorSheet: some View {
        NavigationStack {
            Form {
                Section("Raspberry Pi 4 Gateway") {
                    LabeledContent("Tailscale IP") {
                        TextField("100.100.2.103", text: $client.piTailscaleIP)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    LabeledContent("WLAN (LAN) IP") {
                        TextField("192.168.0.87", text: $client.piLanIP)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                    }
                }
                Section("Windows HomeServer PC") {
                    LabeledContent("Tailscale IP") {
                        TextField("100.77.172.23", text: $client.pcTailscaleIP)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                    }
                    LabeledContent("WLAN (LAN) IP") {
                        TextField("192.168.0.33", text: $client.pcLanIP)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                    }
                }
            }
            .navigationTitle("Host-Adressen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") {
                        showIPEditor = false
                        Task { await client.resolveActiveHost() }
                    }
                }
            }
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
