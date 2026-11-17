import SwiftUI
import Charts

struct JellyControlView: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.openURL) private var openURL
    @State private var showShutdownConfirm = false
    @State private var selectedModeServer = true

    private var status: JellyStatusResponse? { client.jellyStatus }
    private var daemon: DaemonData? { status?.daemonData }
    private var isOnline: Bool { (status?.pcOnline ?? false) && daemon != nil }
    private var isServerMode: Bool { daemon?.serverMode ?? true }

    private var stateAccent: Color {
        guard let status else { return .gray }
        if isOnline { return isServerMode ? .green : .purple }
        if status.pcOnline { return .orange }
        return .red
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    heroCard

                    if isOnline {
                        onlineControls
                    } else {
                        wakeButton
                    }

                    if isOnline, let hw = daemon?.hardware {
                        hardwareSection(hw)
                    }

                    servicesSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(
                LinearGradient(
                    colors: [stateAccent.opacity(0.18), Color(red: 0.03, green: 0.04, blue: 0.08)],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
            )
            .navigationTitle("JellyControl")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 10) {
                        Label(client.activeRouteLabel, systemImage: client.activeRouteLabel == "WLAN" ? "wifi" : "network")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Button {
                            Haptics.light()
                            Task { await client.refreshJelly() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .refreshable {
                await client.refreshJelly()
            }
            .confirmationDialog(
                "PC in Ruhezustand versetzen?",
                isPresented: $showShutdownConfirm,
                titleVisibility: .visible
            ) {
                Button("Ruhezustand (0W Standby)", role: .destructive) {
                    Task { await client.sendJellyAction("/api/shutdown", fallbackMsg: "PC geht in Ruhezustand…") }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Die SmartLife-Steckdose bleibt eingeschaltet. Deine Windows-Sitzung bleibt gespeichert und kann jederzeit per Wake-on-LAN geweckt werden.")
            }
        }
        .task {
            while !Task.isCancelled {
                await client.refreshJelly()
                if let sm = client.jellyStatus?.daemonData?.serverMode {
                    selectedModeServer = sm
                }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(stateAccent.opacity(0.22))
                    .frame(width: 82, height: 82)
                Circle()
                    .fill(stateAccent.gradient)
                    .frame(width: 60, height: 60)
                    .shadow(color: stateAccent.opacity(0.55), radius: 14)
                Image(systemName: heroSymbol)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text(heroTitle)
                    .font(.title2.bold())
                Text(heroSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Status Pills
            HStack(spacing: 8) {
                if let lat = status?.latencyMs, status?.pcOnline == true {
                    statusPill("\(Int(lat.rounded())) ms", color: .green)
                }
                if let d = daemon {
                    statusPill(d.nordvpn == true ? "VPN AN" : "VPN AUS", color: d.nordvpn == true ? .green : .red)
                    if let up = d.uptimeSeconds {
                        statusPill("Up \(formatUptime(up))", color: .cyan)
                    }
                    if d.screenLocked == true {
                        statusPill("Gesperrt", color: .orange)
                    }
                }
            }

            // 4 Live Metrics
            let hw = daemon?.hardware
            let watt = isOnline ? Int((hw?.estSystemW ?? 100).rounded()) : (status?.pcOnline == true ? 80 : 0)
            let kwh = status?.config?.kwhPriceEur ?? 0.32
            let ctH = String(format: "%.1f ct/h", (Double(watt) / 1000.0) * kwh * 100.0)

            HStack(spacing: 8) {
                metricBox(title: "STROM", value: "\(watt) W", sub: ctH, color: .orange)
                metricBox(title: "CPU", value: isOnline ? "\(Int((hw?.cpuPct ?? 0).rounded()))%" : "–", sub: isOnline ? "\(Int((hw?.cpuPowerW ?? 0).rounded())) W" : "aus", color: .cyan)
                metricBox(title: "GPU", value: isOnline ? "\(Int((hw?.gpuTempC ?? 0).rounded()))°C" : "–", sub: isOnline ? "\(Int((hw?.gpuPowerW ?? 0).rounded())) W" : "aus", color: .purple)
                metricBox(title: "RAM", value: isOnline ? "\(Int((hw?.ramPct ?? 0).rounded()))%" : "–", sub: isOnline ? String(format: "%.0f GB", hw?.ramUsedGb ?? 0) : "aus", color: .green)
            }

            // Native Apple Charts Power Sparkline
            if let history = status?.powerHistory, history.count >= 2 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Leistungsverlauf")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        let minW = Int((history.map(\.w).min() ?? 0).rounded())
                        let maxW = Int((history.map(\.w).max() ?? 0).rounded())
                        Text("Min \(minW) W · Max \(maxW) W")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Chart(history) { sample in
                        AreaMark(
                            x: .value("Zeit", sample.t),
                            y: .value("Watt", sample.w)
                        )
                        .foregroundStyle(LinearGradient(colors: [.orange.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("Zeit", sample.t),
                            y: .value("Watt", sample.w)
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 44)
                }
                .padding(10)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Controls

    private var wakeButton: some View {
        Button {
            Task { await client.sendJellyAction("/api/wake", fallbackMsg: "Wake-on-LAN gesendet!") }
        } label: {
            Label("PC Aufwecken (Wake-on-LAN)", systemImage: "bolt.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(LinearGradient(colors: [.green, .teal], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)
        }
    }

    private var onlineControls: some View {
        VStack(spacing: 12) {
            // Primary Jellyfin launch button
            Button {
                Haptics.light()
                let port = status?.config?.jellyfinPort ?? 8096
                if let url = URL(string: "http://\(client.resolvedPcHost):\(port)") {
                    openURL(url)
                }
            } label: {
                HStack {
                    Image(systemName: "play.tv.fill")
                    Text(jellyfinButtonTitle)
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(.white)
            }

            // Native Segmented Switch: HomeServer <-> Gaming
            Picker("Modus", selection: $selectedModeServer) {
                Text("⚡ HomeServer").tag(true)
                Text("🎮 Gaming").tag(false)
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedModeServer) { _, newVal in
                guard newVal != (daemon?.serverMode ?? true) else { return }
                let path = newVal ? "/api/services/start" : "/api/services/stop"
                let msg = newVal ? "HomeServer-Modus gestartet!" : "Gaming-Modus aktiviert!"
                Task { await client.sendJellyAction(path, fallbackMsg: msg) }
            }

            // DarkRoom RGB & Hibernate
            HStack(spacing: 10) {
                let rgbOff = daemon?.rgbKilled == true
                Button {
                    Task { await client.sendJellyAction("/api/rgb/toggle", fallbackMsg: "RGB umgeschaltet!") }
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: rgbOff ? "lightbulb.slash.fill" : "lightbulb.fill")
                                .foregroundStyle(rgbOff ? .indigo : .yellow)
                            Spacer()
                            Text(rgbOff ? "DARK" : "AN")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background((rgbOff ? Color.indigo : Color.green).opacity(0.22), in: Capsule())
                        }
                        Text("DarkRoom RGB").font(.subheadline.bold())
                        Text(rgbOff ? "Beleuchtung aus" : "Tastatur & Maus an").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.09), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.warning()
                    showShutdownConfirm = true
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "moon.zzz.fill")
                                .foregroundStyle(.pink)
                            Spacer()
                            Text("0W")
                                .font(.caption2.bold())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.pink.opacity(0.2), in: Capsule())
                        }
                        Text("Ruhezustand").font(.subheadline.bold())
                        Text("Sicher schlafen").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.pink.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.pink.opacity(0.28), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Hardware Bars

    private func hardwareSection(_ hw: HardwareTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LIVE HARDWARE")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                progressRow(title: "CPU", detail: "\(Int((hw.cpuPct ?? 0).rounded()))% · \(Int((hw.cpuPowerW ?? 0).rounded())) W", value: (hw.cpuPct ?? 0) / 100.0, tint: .cyan)
                progressRow(title: "GPU", detail: "\(Int((hw.gpuTempC ?? 0).rounded()))°C · \(Int((hw.gpuPowerW ?? 0).rounded())) W", value: min(1.0, (hw.gpuPowerW ?? 0) / 320.0), tint: .purple)
                let ramPct = (hw.ramPct ?? 0) / 100.0
                progressRow(title: "RAM", detail: String(format: "%.1f / %.0f GB", hw.ramUsedGb ?? 0, hw.ramTotalGb ?? 0), value: ramPct, tint: .green)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    // MARK: - Services Grid

    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("DIENSTE & APPS")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text(client.resolvedPcHost)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: cols, spacing: 10) {
                serviceTile("Jellyfin", sub: status?.jellyfinInfo?.version.map { "v\($0)" } ?? ":8096", icon: "play.tv", active: daemon?.jellyfin == true, port: status?.config?.jellyfinPort ?? 8096)
                serviceTile("qBittorrent", sub: "Killswitch", icon: "arrow.down.circle", active: daemon?.qbittorrent == true, port: status?.config?.qbittorrentPort ?? 8080)
                serviceTile("Sonarr", sub: "Serien", icon: "tv", active: daemon?.sonarr == true, port: status?.config?.sonarrPort ?? 8989)
                serviceTile("Radarr", sub: "Filme", icon: "film", active: daemon?.radarr == true, port: status?.config?.radarrPort ?? 7878)
                serviceTile("Prowlarr", sub: "Indexer", icon: "magnifyingglass", active: daemon?.prowlarr == true, port: status?.config?.prowlarrPort ?? 9696)
                serviceTile("NordVPN", sub: daemon?.nordvpnIp ?? "Getrennt", icon: "shield.checkered", active: daemon?.nordvpn == true, port: nil)
                serviceTile("Moonlight", sub: "Sunshine", icon: "gamecontroller", active: daemon?.sunshine == true, port: nil)
                serviceTile("RustDesk", sub: "Remote PC", icon: "desktopcomputer", active: daemon?.rustdesk == true, port: nil)
                serviceTile("Windows SSH", sub: "Port 22", icon: "terminal", active: daemon?.ssh == true, port: nil)
                serviceTile("Tailscale", sub: "Mesh VPN", icon: "network", active: daemon?.tailscale == true, port: nil)
            }
        }
    }

    private func serviceTile(_ name: String, sub: String, icon: String, active: Bool, port: Int?) -> some View {
        Button {
            guard let port else { return }
            Haptics.light()
            if let url = URL(string: "http://\(client.resolvedPcHost):\(port)") {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(active ? .cyan : .secondary)
                    Spacer()
                    Text(active ? "LÄUFT" : "AUS")
                        .font(.system(size: 9.5, weight: .heavy))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((active ? Color.green : Color.red).opacity(0.18), in: Capsule())
                        .foregroundStyle(active ? .green : .red)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.bold()).foregroundStyle(.primary)
                    Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var heroSymbol: String {
        if isOnline { return isServerMode ? "bolt.fill" : "gamecontroller.fill" }
        if status?.pcOnline == true { return "lock.fill" }
        return "moon.zzz.fill"
    }

    private var heroTitle: String {
        if let err = client.jellyError, status == nil { return err }
        if isOnline { return isServerMode ? "HomeServer Aktiv" : "Gaming-Modus" }
        if status?.pcOnline == true { return "PC am Lockscreen" }
        return "PC im Ruhezustand"
    }

    private var heroSubtitle: String {
        if isOnline {
            let ver = status?.jellyfinInfo?.version.map { " · Jellyfin v\($0)" } ?? ""
            return (isServerMode ? "Alle Streaming-Dienste laufen" : "Server-Dienste pausiert") + ver
        }
        if status?.pcOnline == true { return "Fährt hoch · warte auf Windows-Daemon" }
        return "0W Standby · bereit für Wake-on-LAN"
    }

    private var jellyfinButtonTitle: String {
        if let v = status?.jellyfinInfo?.version, !v.isEmpty {
            return "Jellyfin öffnen (v\(v))"
        }
        return "Jellyfin öffnen"
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.07), in: Capsule())
    }

    private func metricBox(title: String, value: String, sub: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).foregroundStyle(color)
            Text(sub).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func progressRow(title: String, detail: String, value: Double, tint: Color) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(detail).font(.caption.bold())
            }
            ProgressView(value: max(0, min(1, value)))
                .tint(tint)
        }
    }

    private func formatUptime(_ sec: Int) -> String {
        let d = sec / 86400
        let h = (sec % 86400) / 3600
        let m = (sec % 3600) / 60
        if d > 0 { return "\(d)T \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
