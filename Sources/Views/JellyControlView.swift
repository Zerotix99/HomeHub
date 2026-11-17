import SwiftUI
import Charts

struct JellyControlView: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.openURL) private var openURL
    @State private var showShutdownConfirm = false
    @State private var pulseOrb = false

    private var status: JellyStatusResponse? { client.jellyStatus }
    private var daemon: DaemonData? { status?.daemonData }
    private var isOnline: Bool { (status?.pcOnline ?? false) && daemon != nil }
    private var isServerMode: Bool { daemon?.serverMode ?? true }

    private var stateAccent: Color {
        guard let status else { return .gray }
        if isOnline { return isServerMode ? HubTheme.emerald : HubTheme.purple }
        if status.pcOnline { return HubTheme.amber }
        return HubTheme.rose
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    PiGatewayBar()

                    heroStatusCard

                    actionDeck

                    if isOnline, let hw = daemon?.hardware {
                        hardwareTelemetryCard(hw)
                    }

                    servicesGridSection
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .background(
                ZStack {
                    HubTheme.bg.ignoresSafeArea()
                    RadialGradient(
                        colors: [stateAccent.opacity(0.22), .clear],
                        center: .top,
                        startRadius: 10,
                        endRadius: 380
                    )
                    .ignoresSafeArea()
                }
            )
            .navigationTitle("JellyControl Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(client.isConnected ? HubTheme.emerald : HubTheme.rose)
                            .frame(width: 8, height: 8)
                        Text(client.activeRouteLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        Task {
                            await client.refreshJelly()
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
                await client.refreshJelly()
            }
            .confirmationDialog(
                "💤 PC in Ruhezustand versetzen?",
                isPresented: $showShutdownConfirm,
                titleVisibility: .visible
            ) {
                Button("Ruhezustand (0W Standby)", role: .destructive) {
                    Task { await client.sendJellyAction("/api/shutdown", fallbackMsg: "PC geht in Ruhezustand (0W)…") }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Der PC wechselt sauber in den 0W-Ruhezustand (Hibernate). Die SmartLife-Steckdose bleibt an, deine Sitzung bleibt erhalten und du kannst ihn jederzeit per Wake-on-LAN wecken.")
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                pulseOrb = true
            }
        }
        .task {
            while !Task.isCancelled {
                await client.refreshJelly()
                try? await Task.sleep(nanoseconds: 3_500_000_000)
            }
        }
    }

    // MARK: - Hero Status Card

    private var heroStatusCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(stateAccent.opacity(0.18))
                    .frame(width: 88, height: 88)
                    .scaleEffect(pulseOrb ? 1.08 : 0.94)

                Circle()
                    .stroke(stateAccent.opacity(0.45), lineWidth: 2)
                    .frame(width: 72, height: 72)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: isOnline
                                ? (isServerMode ? [HubTheme.emerald, Color.teal] : [HubTheme.purple, HubTheme.pink])
                                : (status?.pcOnline == true ? [HubTheme.amber, .orange] : [HubTheme.rose, Color.red.opacity(0.7)]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 58, height: 58)
                    .shadow(color: stateAccent.opacity(0.6), radius: 16)

                Image(systemName: heroSymbol)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text(heroTitle)
                    .font(.system(size: 21, weight: .heavy))
                Text(heroSubtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Status Chips Row (just like Web Dashboard!)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    GlowChip(
                        text: daemon?.hostname ?? (status?.pcOnline == true ? "Lockscreen" : "PC Offline"),
                        dotColor: isOnline ? HubTheme.emerald : (status?.pcOnline == true ? HubTheme.amber : HubTheme.rose),
                        icon: "desktopcomputer"
                    )
                    GlowChip(
                        text: isOnline ? (isServerMode ? "HomeServer" : "Gaming") : "Standby",
                        dotColor: isOnline ? (isServerMode ? HubTheme.emerald : HubTheme.purple) : HubTheme.rose,
                        icon: isServerMode ? "server.rack" : "gamecontroller.fill"
                    )
                    GlowChip(
                        text: daemon?.nordvpn == true ? "VPN \(daemon?.nordvpnIp ?? "AN")" : "VPN AUS",
                        dotColor: daemon?.nordvpn == true ? HubTheme.emerald : HubTheme.rose,
                        icon: "shield.lefthalf.filled"
                    )
                    if let lat = status?.latencyMs, status?.pcOnline == true {
                        GlowChip(text: "\(Int(lat.rounded())) ms", dotColor: HubTheme.emerald, icon: "bolt.horizontal.fill")
                    }
                    if let up = daemon?.uptimeSeconds {
                        GlowChip(text: "Up \(formatUptime(up))", dotColor: HubTheme.sky, icon: "clock.fill")
                    }
                }
            }

            // 4 Mini Hardware Gauges
            let hw = daemon?.hardware
            let watt = isOnline ? Int((hw?.estSystemW ?? 100).rounded()) : (status?.pcOnline == true ? 80 : 0)
            let kwh = status?.config?.kwhPriceEur ?? 0.32
            let ctH = String(format: "%.1f ct/h", (Double(watt) / 1000.0) * kwh * 100.0)

            HStack(spacing: 8) {
                miniStatTile(icon: "bolt.fill", title: "STROM", value: "~\(watt) W", sub: ctH, color: HubTheme.amber)
                miniStatTile(icon: "cpu", title: "CPU", value: isOnline ? "\(Int((hw?.cpuPct ?? 0).rounded()))%" : "–", sub: isOnline ? "\(Int((hw?.cpuPowerW ?? 0).rounded())) W" : "0 W", color: HubTheme.sky)
                miniStatTile(icon: "thermometer.medium", title: "GPU", value: isOnline ? "\(Int((hw?.gpuTempC ?? 0).rounded()))°C" : "–", sub: isOnline ? "\(Int((hw?.gpuPowerW ?? 0).rounded())) W" : "0 W", color: HubTheme.purple)
                miniStatTile(icon: "memorychip", title: "RAM", value: isOnline ? "\(Int((hw?.ramPct ?? 0).rounded()))%" : "–", sub: isOnline ? String(format: "%.0f/%.0fG", hw?.ramUsedGb ?? 0, hw?.ramTotalGb ?? 32) : "aus", color: HubTheme.emerald)
            }

            // Live Power Sparkline
            if let history = status?.powerHistory, history.count >= 2 {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Label("Live Stromverlauf", systemImage: "waveform.path.ecg")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(HubTheme.amber)
                        Spacer()
                        let minW = Int((history.map(\.w).min() ?? 0).rounded())
                        let maxW = Int((history.map(\.w).max() ?? 0).rounded())
                        Text("Min \(minW)W • Max \(maxW)W")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Chart(history) { sample in
                        AreaMark(x: .value("T", sample.t), y: .value("W", sample.w))
                            .foregroundStyle(LinearGradient(colors: [HubTheme.amber.opacity(0.38), .clear], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("T", sample.t), y: .value("W", sample.w))
                            .foregroundStyle(HubTheme.amber)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 36)
                }
                .padding(10)
                .background(HubTheme.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(16)
        .hubCard(cornerRadius: 22, highlight: stateAccent)
    }

    // MARK: - Action Deck (Rich Symbolic Buttons like Web UI!)

    private var actionDeck: some View {
        VStack(spacing: 10) {
            // Wake-on-LAN or Jellyfin Primary Hero Button
            if !isOnline {
                Button {
                    Task { await client.sendJellyAction("/api/wake", fallbackMsg: "⚡ Wake-on-LAN gesendet!") }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "bolt.fill")
                            .font(.title3.bold())
                        VStack(alignment: .leading, spacing: 1) {
                            Text("PC Starten (Wake-on-LAN)")
                                .font(.system(size: 15.5, weight: .heavy))
                            Text("Weckt PC auf & startet HomeServer-Dienste")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                        Spacer()
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title3)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(LinearGradient(colors: [HubTheme.emerald, Color(red: 0.02, green: 0.58, blue: 0.41)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                    .shadow(color: HubTheme.emerald.opacity(0.35), radius: 12, y: 5)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    Haptics.light()
                    let port = status?.config?.jellyfinPort ?? 8096
                    if let url = URL(string: "http://\(client.resolvedPcHost):\(port)") {
                        openURL(url)
                    }
                } label: {
                    HStack(spacing: 12) {
                        IconBadge(symbol: "play.tv.fill", colors: [HubTheme.sky, HubTheme.indigo], size: 40, iconSize: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Jellyfin Stream öffnen")
                                .font(.system(size: 15.5, weight: .heavy))
                            Text("\(client.resolvedPcHost):\(status?.config?.jellyfinPort ?? 8096)\(status?.jellyfinInfo?.version.map { " • v\($0)" } ?? "")")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.title3)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(LinearGradient(colors: [Color(red: 0.01, green: 0.52, blue: 0.78), HubTheme.indigo], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.white)
                    .shadow(color: HubTheme.sky.opacity(0.3), radius: 12, y: 5)
                }
                .buttonStyle(.plain)
            }

            // 2 Mode Action Tiles: HomeServer vs Gaming
            HStack(spacing: 10) {
                Button {
                    Task { await client.sendJellyAction("/api/services/start", fallbackMsg: "▶️ HomeServer-Dienste gestartet!") }
                } label: {
                    HStack(spacing: 10) {
                        IconBadge(symbol: "play.fill", colors: [HubTheme.indigo, HubTheme.sky], size: 34, iconSize: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Server-Dienste")
                                .font(.system(size: 13, weight: .bold))
                            Text(isOnline && isServerMode ? "Aktiv • Läuft" : "Alle starten")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .hubCard(cornerRadius: 16, highlight: (isOnline && isServerMode) ? HubTheme.indigo : nil)
                }
                .buttonStyle(.plain)

                Button {
                    Task { await client.sendJellyAction("/api/services/stop", fallbackMsg: "🎮 Gaming-Modus aktiviert!") }
                } label: {
                    HStack(spacing: 10) {
                        IconBadge(symbol: "gamecontroller.fill", colors: [HubTheme.pink, HubTheme.purple], size: 34, iconSize: 14)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Gaming-Modus")
                                .font(.system(size: 13, weight: .bold))
                            Text(isOnline && !isServerMode ? "Aktiv • Max FPS" : "Dienste pausieren")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .hubCard(cornerRadius: 16, highlight: (isOnline && !isServerMode) ? HubTheme.pink : nil)
                }
                .buttonStyle(.plain)
            }

            // RGB DarkRoom & Hibernate Row
            HStack(spacing: 10) {
                let rgbOff = daemon?.rgbKilled == true
                Button {
                    Task { await client.sendJellyAction("/api/rgb/toggle", fallbackMsg: "💡 RGB-Beleuchtung umgeschaltet!") }
                } label: {
                    HStack(spacing: 10) {
                        IconBadge(
                            symbol: rgbOff ? "moon.stars.fill" : "lightbulb.fill",
                            colors: rgbOff ? [HubTheme.indigo, HubTheme.purple] : [HubTheme.amber, .orange],
                            size: 34,
                            iconSize: 15
                        )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(rgbOff ? "RGB Einschalten" : "DarkRoom RGB")
                                .font(.system(size: 13, weight: .bold))
                            Text(rgbOff ? "Aktuell AUS (Dark)" : "Razer & Roccat aus")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .hubCard(cornerRadius: 16)
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.warning()
                    showShutdownConfirm = true
                } label: {
                    HStack(spacing: 10) {
                        IconBadge(symbol: "powersleep", colors: [HubTheme.rose, HubTheme.pink], size: 34, iconSize: 15)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Ruhezustand")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.76))
                            Text("0W Hibernate")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .hubCard(cornerRadius: 16, highlight: HubTheme.rose.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Detailed Hardware Telemetry

    private func hardwareTelemetryCard(_ hw: HardwareTelemetry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Hardware-Auslastung", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(daemon?.monitorsAttached ?? 1) Monitor(e) aktiv")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            hwBar(label: "CPU Auslastung", right: "\(Int((hw.cpuPct ?? 0).rounded()))% • \(Int((hw.cpuPowerW ?? 0).rounded())) W", progress: (hw.cpuPct ?? 0) / 100.0, colors: [HubTheme.sky, HubTheme.indigo])
            hwBar(label: "GPU Leistung & Temp", right: "\(Int((hw.gpuTempC ?? 0).rounded()))°C • \(Int((hw.gpuPowerW ?? 0).rounded())) W", progress: min(1.0, (hw.gpuPowerW ?? 0) / 300.0), colors: [HubTheme.purple, HubTheme.pink])
            hwBar(label: "Arbeitsspeicher (RAM)", right: String(format: "%.1f / %.0f GB (%d%%)", hw.ramUsedGb ?? 0, hw.ramTotalGb ?? 32, Int((hw.ramPct ?? 0).rounded())), progress: (hw.ramPct ?? 0) / 100.0, colors: [HubTheme.emerald, HubTheme.sky])
        }
        .padding(14)
        .hubCard(cornerRadius: 18)
    }

    // MARK: - Services Grid (All 10 services with rich icons!)

    private var servicesGridSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Dienste & Streaming-Apps", systemImage: "square.grid.2x2.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Ziel: \(client.resolvedPcHost)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(HubTheme.sky)
            }
            .padding(.horizontal, 4)

            let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: cols, spacing: 10) {
                serviceCard(name: "Jellyfin Server", desc: status?.jellyfinInfo?.version.map { "v\($0) • Port 8096" } ?? "Port 8096", symbol: "play.tv.fill", colors: [HubTheme.purple, HubTheme.sky], active: daemon?.jellyfin == true, port: status?.config?.jellyfinPort ?? 8096)
                serviceCard(name: "NordVPN Tunnel", desc: daemon?.nordvpnIp.map { "IP: \($0)" } ?? "Getrennt", symbol: "shield.checkered", colors: [HubTheme.emerald, HubTheme.sky], active: daemon?.nordvpn == true, port: nil)
                serviceCard(name: "qBittorrent", desc: "Killswitch aktiv • :8080", symbol: "arrow.down.circle.fill", colors: [HubTheme.sky, HubTheme.indigo], active: daemon?.qbittorrent == true, port: status?.config?.qbittorrentPort ?? 8080)
                serviceCard(name: "Moonlight", desc: "Sunshine • Port 47990", symbol: "gamecontroller.fill", colors: [HubTheme.amber, HubTheme.rose], active: daemon?.sunshine == true, port: nil)
                serviceCard(name: "Sonarr (Serien)", desc: "Web-UI • Port 8989", symbol: "tv.fill", colors: [HubTheme.sky, HubTheme.emerald], active: daemon?.sonarr == true, port: status?.config?.sonarrPort ?? 8989)
                serviceCard(name: "Radarr (Filme)", desc: "Web-UI • Port 7878", symbol: "film.fill", colors: [HubTheme.amber, .orange], active: daemon?.radarr == true, port: status?.config?.radarrPort ?? 7878)
                serviceCard(name: "Prowlarr Indexer", desc: "Web-UI • Port 9696", symbol: "magnifyingglass.circle.fill", colors: [HubTheme.indigo, HubTheme.purple], active: daemon?.prowlarr == true, port: status?.config?.prowlarrPort ?? 9696)
                serviceCard(name: "RustDesk", desc: "Remote Desktop", symbol: "display", colors: [HubTheme.emerald, .teal], active: daemon?.rustdesk == true, port: nil)
                serviceCard(name: "Windows SSH", desc: "Port 22 (magnu)", symbol: "terminal.fill", colors: [.gray, HubTheme.indigo], active: daemon?.ssh == true, port: nil)
                serviceCard(
                    name: "Tastatur & Maus",
                    desc: daemon?.rgbKilled == true ? "DarkRoom aktiv" : "Razer & Roccat an",
                    symbol: "lightbulb.fill",
                    colors: [HubTheme.amber, HubTheme.pink],
                    active: daemon?.rgbKilled != true,
                    port: nil,
                    customTap: {
                        Task { await client.sendJellyAction("/api/rgb/toggle", fallbackMsg: "💡 RGB umgeschaltet!") }
                    }
                )
            }
        }
    }

    private func serviceCard(
        name: String,
        desc: String,
        symbol: String,
        colors: [Color],
        active: Bool,
        port: Int?,
        customTap: (() -> Void)? = nil
    ) -> some View {
        Button {
            if let customTap {
                customTap()
                return
            }
            guard let port else { return }
            Haptics.light()
            if let url = URL(string: "http://\(client.resolvedPcHost):\(port)") {
                openURL(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    IconBadge(symbol: symbol, colors: colors, size: 34, iconSize: 15)
                    Spacer()
                    StatusBadgePill(text: active ? "LÄUFT" : "AUS", active: active)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(name)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if port != nil {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(HubTheme.sky)
                        }
                    }
                    Text(desc)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .hubCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var heroSymbol: String {
        if isOnline { return isServerMode ? "bolt.fill" : "gamecontroller.fill" }
        if status?.pcOnline == true { return "lock.fill" }
        return "powersleep"
    }

    private var heroTitle: String {
        if let err = client.jellyError, status == nil { return err }
        if isOnline { return isServerMode ? "HomeServer Aktiv" : "Gaming-Modus Aktiv" }
        if status?.pcOnline == true { return "PC am Lockscreen" }
        return "PC Ausgeschaltet (0W)"
    }

    private var heroSubtitle: String {
        if isOnline {
            let host = daemon?.hostname ?? "PC"
            return host + (isServerMode ? " • Alle Streaming-Dienste laufen" : " • Server-Dienste pausiert für Spiele")
        }
        if status?.pcOnline == true { return "Netzwerk aktiv • warte auf Windows-Daemon" }
        return "Bereit zum Aufwecken via Wake-on-LAN"
    }

    private func miniStatTile(icon: String, title: String, value: String, sub: String, color: Color) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                Text(title).font(.system(size: 9, weight: .heavy)).foregroundStyle(.secondary)
            }
            Text(value).font(.system(size: 13.5, weight: .heavy)).foregroundStyle(color).lineLimit(1)
            Text(sub).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(HubTheme.cardElevated.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
    }

    private func hwBar(label: String, right: String, progress: Double, colors: [Color]) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text(label).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(right).font(.system(size: 11.5, weight: .bold))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * CGFloat(max(0, min(1, progress)))))
                }
            }
            .frame(height: 7)
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
