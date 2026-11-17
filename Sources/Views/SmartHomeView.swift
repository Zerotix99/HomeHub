import SwiftUI

enum SmartRoomFilter: String, CaseIterable, Identifiable {
    case all = "Alle Räume"
    case living = "Wohnzimmer"
    case bath = "Badezimmer"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2.fill"
        case .living: return "sofa.fill"
        case .bath: return "shower.fill"
        }
    }
}

struct SmartHomeView: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.openURL) private var openURL

    @State private var selectedRoom: SmartRoomFilter = .all
    @State private var selectedLight: SmartLightItem?
    @State private var masterBrightness: Double = 100

    private var state: SmartHomeStateResponse? { client.smartHomeState }
    private var lights: [SmartLightItem] {
        guard let all = state?.lights else { return [] }
        if selectedRoom == .all { return all }
        return all.filter { $0.room.lowercased() == selectedRoom.rawValue.lowercased() }
    }
    private var devices: [SmartDeviceItem] {
        guard let all = state?.devices else { return [] }
        if selectedRoom == .all { return all }
        return all.filter { $0.room.lowercased() == selectedRoom.rawValue.lowercased() }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // 1. Apple Home Top Summary Pills
                    topSummaryStrip

                    // 2. Room Filter Segmented Pills
                    roomFilterStrip

                    // 3. Apple Home Scenes Section
                    scenesSection

                    // 4. Lights Section (Wohnzimmer WiZ v2 RGB+CCT)
                    if !lights.isEmpty {
                        lightsSection
                    }

                    // 5. Badezimmer Section (Echo Show 5 TECHO5 & Waschmaschine)
                    if selectedRoom == .all || selectedRoom == .bath {
                        roomDevicesSection(roomName: "Badezimmer", roomIcon: "shower.fill", roomColor: HubTheme.sky)
                    }

                    // 6. Wohnzimmer Smart Home Devices Section (Refoss, Kasa, Aqara, HomePod, Chromecast, PC Plug)
                    if selectedRoom == .all || selectedRoom == .living {
                        roomDevicesSection(roomName: "Wohnzimmer", roomIcon: "sofa.fill", roomColor: HubTheme.emerald)
                    }

                    // 7. Home Assistant & TECHO5 Quick Access Footer Card
                    homeAssistantBridgeCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .background(
                ZStack {
                    HubTheme.bg.ignoresSafeArea()
                    RadialGradient(
                        colors: [
                            (state?.summary.lightsOn ?? 0) > 0 ? HubTheme.amber.opacity(0.18) : HubTheme.sky.opacity(0.14),
                            .clear
                        ],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: 420
                    )
                    .ignoresSafeArea()
                }
            )
            .navigationTitle("Mein Zuhause")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill((state?.haOnline ?? false) ? HubTheme.emerald : HubTheme.amber)
                            .frame(width: 8, height: 8)
                        Text((state?.haOnline ?? false) ? "HomeKit + HA" : "Local Control")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        Task { await client.refreshSmartHome() }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title3)
                            .foregroundStyle(HubTheme.amber)
                    }
                }
            }
            .refreshable {
                await client.refreshSmartHome()
            }
            .sheet(item: $selectedLight) { light in
                LightDetailSheet(light: light)
            }
        }
        .task {
            await client.refreshSmartHome()
            if let firstB = client.smartHomeState?.lights.first?.brightness {
                masterBrightness = Double(firstB)
            }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await client.refreshSmartHome()
            }
        }
    }

    // MARK: - 1. Top Summary Strip (Apple Home Style)

    private var topSummaryStrip: some View {
        let lightsOn = state?.summary.lightsOn ?? 0
        let lightsTotal = state?.summary.lightsTotal ?? 3
        let devsOnline = state?.summary.devicesOnline ?? 0
        let watts = Int((state?.summary.powerWatts ?? 0).rounded())

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                homeStatusPill(
                    icon: "lightbulb.fill",
                    title: lightsOn > 0 ? "\(lightsOn)/\(lightsTotal) Lichter An" : "Lichter Aus",
                    subtitle: "Wohnzimmer WiZ",
                    color: lightsOn > 0 ? HubTheme.amber : .gray,
                    active: lightsOn > 0
                ) {
                    Task { await client.controlSmartLight(id: "all", state: lightsOn == 0) }
                }

                homeStatusPill(
                    icon: "display",
                    title: "Echo Show 5",
                    subtitle: (state?.echoShowOnline ?? true) ? "Badezimmer • TECHO5" : "Offline",
                    color: HubTheme.sky,
                    active: state?.echoShowOnline ?? true
                ) {
                    selectedRoom = .bath
                }

                homeStatusPill(
                    icon: "powerplug.fill",
                    title: "\(devsOnline) Geräte",
                    subtitle: "Wohn- & Badezimmer",
                    color: HubTheme.emerald,
                    active: true
                ) {
                    selectedRoom = .all
                }

                homeStatusPill(
                    icon: "bolt.fill",
                    title: "~\(watts) W",
                    subtitle: "Gesamt-Last",
                    color: HubTheme.purple,
                    active: watts > 20
                ) {}
            }
        }
    }

    private func homeStatusPill(icon: String, title: String, subtitle: String, color: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            Haptics.light()
            action()
        }) {
            HStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(active ? color.opacity(0.24) : Color.white.opacity(0.06))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(active ? color : .secondary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .hubCard(cornerRadius: 22, highlight: active ? color.opacity(0.6) : nil)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Room Filter Strip

    private var roomFilterStrip: some View {
        HStack(spacing: 8) {
            ForEach(SmartRoomFilter.allCases) { room in
                let isSel = selectedRoom == room
                Button {
                    Haptics.light()
                    withAnimation(.spring(response: 0.25)) {
                        selectedRoom = room
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: room.symbol)
                            .font(.system(size: 11.5, weight: .bold))
                        Text(room.rawValue)
                            .font(.system(size: 12.5, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(isSel ? HubTheme.sky.opacity(0.22) : HubTheme.card, in: Capsule())
                    .overlay(Capsule().stroke(isSel ? HubTheme.sky.opacity(0.65) : HubTheme.border, lineWidth: 1))
                    .foregroundStyle(isSel ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 3. Scenes Section (Apple Home Style)

    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Szenen & Stimmungen", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    sceneTile(id: "cozy", title: "Cozy Abend", sub: "Warmes Licht 80%", icon: "flame.fill", colors: [HubTheme.amber, .orange])
                    sceneTile(id: "bright", title: "Hell & Fokus", sub: "Tageslicht 100%", icon: "sun.max.fill", colors: [HubTheme.sky, HubTheme.emerald])
                    sceneTile(id: "cinema", title: "Kino & Stream", sub: "Dimmen 15% + RGB Aus", icon: "film.stack.fill", colors: [HubTheme.purple, HubTheme.indigo])
                    sceneTile(id: "gaming", title: "Gaming Vibe", sub: "Sunset + Max FPS", icon: "gamecontroller.fill", colors: [HubTheme.pink, HubTheme.purple])
                    sceneTile(id: "night", title: "Nachtlicht", sub: "Sanftes 10% Warm", icon: "moon.stars.fill", colors: [HubTheme.indigo, .blue])
                    sceneTile(id: "all_off", title: "Lichter Aus", sub: "Alle Lampen aus", icon: "power", colors: [HubTheme.rose, .red])
                }
            }
        }
    }

    private func sceneTile(id: String, title: String, sub: String, icon: String, colors: [Color]) -> some View {
        Button {
            Task { await client.triggerSmartScene(id) }
        } label: {
            HStack(spacing: 10) {
                IconBadge(symbol: icon, colors: colors, size: 36, iconSize: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                    Text(sub)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .hubCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Interactive Apple HomeKit Light Cards

    private var lightsSection: some View {
        let anyOn = lights.contains(where: \.isOn)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Wohnzimmer Beleuchtung (WiZ v2)", systemImage: "lightbulb.2.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await client.controlSmartLight(id: "all", state: !anyOn) }
                } label: {
                    Text(anyOn ? "Alle Aus" : "Alle An")
                        .font(.system(size: 11.5, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(anyOn ? HubTheme.amber.opacity(0.2) : Color.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(anyOn ? HubTheme.amber : .secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            // Master Brightness Bar for all Wohnzimmer lights
            HStack(spacing: 10) {
                Image(systemName: anyOn ? "sun.max.fill" : "sun.min")
                    .foregroundStyle(anyOn ? HubTheme.amber : .secondary)
                Text("Alle Lampen")
                    .font(.system(size: 12.5, weight: .bold))
                Slider(
                    value: $masterBrightness,
                    in: 10...100,
                    step: 5,
                    onEditingChanged: { editing in
                        if !editing {
                            Task {
                                await client.controlSmartLight(id: "all", state: true, brightness: Int(masterBrightness))
                            }
                        }
                    }
                )
                .tint(HubTheme.amber)
                Text("\(Int(masterBrightness))%")
                    .font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(HubTheme.amber)
                    .frame(width: 38, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .hubCard(cornerRadius: 14)

            let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(lights) { light in
                    HomeKitLightTile(
                        light: light,
                        onToggle: {
                            Task { await client.controlSmartLight(id: light.id, state: !light.isOn) }
                        },
                        onBrightnessChange: { newBri in
                            Task { await client.controlSmartLight(id: light.id, state: true, brightness: newBri) }
                        },
                        onOpenDetail: {
                            Haptics.light()
                            selectedLight = light
                        }
                    )
                }
            }
        }
    }

    // MARK: - 5 & 6. Room Devices Section (Badezimmer & Wohnzimmer)

    private func roomDevicesSection(roomName: String, roomIcon: String, roomColor: Color) -> some View {
        let roomDevs = (state?.devices ?? []).filter { $0.room.lowercased() == roomName.lowercased() }
        return Group {
            if !roomDevs.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(roomName, systemImage: roomIcon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(roomColor)
                        Spacer()
                        Text("\(roomDevs.count) Geräte")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)

                    let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(roomDevs) { dev in
                            HomeKitDeviceTile(device: dev) {
                                Task { await client.toggleSmartDevice(dev) }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 7. Home Assistant & TECHO5 Bridge Card

    private var homeAssistantBridgeCard: some View {
        let haOnline = state?.haOnline ?? false
        let haURL = "http://\(client.activePiHost):8123"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconBadge(symbol: "house.and.flag.fill", colors: [HubTheme.sky, HubTheme.indigo], size: 38, iconSize: 17)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Home Assistant & Echo Show 5 (TECHO5)")
                        .font(.system(size: 14, weight: .heavy))
                    Text(haOnline ? "Pi 4 Server (:8123) aktiv • Synchron mit TECHO5" : "Home Assistant startet auf Port 8123…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadgePill(text: haOnline ? "HA AKTIV" : "STARTET", active: haOnline)
            }

            HStack(spacing: 8) {
                Button {
                    Haptics.light()
                    if let u = URL(string: haURL) { openURL(u) }
                } label: {
                    Label("Home Assistant öffnen (:8123)", systemImage: "safari.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(LinearGradient(colors: [HubTheme.sky, HubTheme.indigo], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 11))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Button {
                    Haptics.light()
                    if let u = URL(string: "http://192.168.0.111:8181") { openURL(u) }
                } label: {
                    Label("TECHO5 Setup", systemImage: "display")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(HubTheme.cardElevated, in: RoundedRectangle(cornerRadius: 11))
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(HubTheme.border, lineWidth: 1))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .hubCard(cornerRadius: 18)
    }
}

// MARK: - HomeKit Light Tile with Touch Slider

private struct HomeKitLightTile: View {
    let light: SmartLightItem
    let onToggle: () -> Void
    let onBrightnessChange: (Int) -> Void
    let onOpenDetail: () -> Void

    @State private var localBri: Double = 100
    @State private var isDragging = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: onToggle) {
                    ZStack {
                        Circle()
                            .fill(light.isOn ? light.accentColor.opacity(0.28) : Color.white.opacity(0.06))
                            .frame(width: 40, height: 40)
                            .shadow(color: light.isOn ? light.accentColor.opacity(0.5) : .clear, radius: 8)
                        Image(systemName: light.isOn ? "lightbulb.fill" : "lightbulb")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(light.isOn ? light.accentColor : .secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onOpenDetail) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .bold))
                        .padding(7)
                        .background(Color.white.opacity(0.07), in: Circle())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(light.name)
                        .font(.system(size: 13.5, weight: .heavy))
                        .foregroundStyle(light.isOn ? .white : .secondary)
                        .lineLimit(1)
                    Text(light.isOn ? "\(Int(localBri))% • \(light.sceneName ?? "Warmweiß")" : "Aus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(light.isOn ? light.accentColor : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            // Interactive Brightness Track along the foot (just like TECHO5 & Apple Home!)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    if light.isOn {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [light.accentColor.opacity(0.7), light.accentColor],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(10, geo.size.width * CGFloat(localBri / 100.0)))
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { val in
                            isDragging = true
                            let pct = max(10, min(100, Double(val.location.x / max(1, geo.size.width)) * 100.0))
                            localBri = pct
                        }
                        .onEnded { _ in
                            isDragging = false
                            Haptics.light()
                            onBrightnessChange(Int(localBri.rounded()))
                        }
                )
            }
            .frame(height: 8)
        }
        .padding(12)
        .hubCard(cornerRadius: 18, highlight: light.isOn ? light.accentColor : nil)
        .onAppear {
            localBri = Double(light.brightness)
        }
        .onChange(of: light.brightness) { _, newVal in
            if !isDragging { localBri = Double(newVal) }
        }
    }
}

// MARK: - HomeKit Device Tile

private struct HomeKitDeviceTile: View {
    let device: SmartDeviceItem
    let onTap: () -> Void

    private var tileColor: Color {
        if !device.online { return .gray }
        switch device.category {
        case "display": return HubTheme.sky
        case "speaker", "media": return HubTheme.purple
        case "bridge": return HubTheme.indigo
        case "pc_plug": return HubTheme.emerald
        default: return device.isOn ? HubTheme.emerald : .gray
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(device.isOn ? tileColor.opacity(0.24) : Color.white.opacity(0.06))
                            .frame(width: 38, height: 38)
                        Image(systemName: device.icon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(device.isOn ? tileColor : .secondary)
                    }
                    Spacer()
                    if device.protectedDevice {
                        HStack(spacing: 3) {
                            Image(systemName: "lock.fill").font(.system(size: 8))
                            Text("SAFE").font(.system(size: 8.5, weight: .heavy))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(HubTheme.emerald.opacity(0.18), in: Capsule())
                        .foregroundStyle(HubTheme.emerald)
                    } else {
                        StatusBadgePill(text: device.isOn ? "AN" : "BEREIT", active: device.isOn, activeColor: tileColor)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(device.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .hubCard(cornerRadius: 18, highlight: device.isOn ? tileColor.opacity(0.55) : nil)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Rich Light Color & Scene Detail Sheet

struct LightDetailSheet: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.dismiss) private var dismiss
    let light: SmartLightItem

    @State private var isOn: Bool = true
    @State private var brightness: Double = 100

    private let colorPresets: [(String, Int, Int, Int, Color)] = [
        ("Warm Amber", 255, 140, 20, .orange),
        ("Sunset Rot", 255, 50, 30, HubTheme.rose),
        ("Cyber Lila", 170, 40, 255, HubTheme.purple),
        ("Neon Pink", 255, 30, 150, HubTheme.pink),
        ("Ozean Blau", 20, 160, 255, HubTheme.sky),
        ("Smaragd", 16, 220, 120, HubTheme.emerald)
    ]

    private let tempPresets: [(String, Int, Color)] = [
        ("Kerzenlicht (2200K)", 2200, .orange),
        ("Warmweiß (2700K)", 2700, HubTheme.amber),
        ("Neutralweiß (4000K)", 4000, .white),
        ("Tageslicht (6500K)", 6500, HubTheme.sky)
    ]

    private let wizScenes: [(Int, String, String)] = [
        (6, "Cozy", "flame.fill"),
        (5, "Kaminfeuer", "fireplace.fill"),
        (1, "Ozean", "water.waves"),
        (3, "Sonnenuntergang", "sun.haze.fill"),
        (4, "Party", "sparkles"),
        (14, "Nachtlicht", "moon.stars.fill"),
        (2, "Romantik", "heart.fill"),
        (7, "Wald", "leaf.fill")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Header Toggle & Brightness
                    VStack(spacing: 12) {
                        HStack {
                            IconBadge(symbol: "lightbulb.fill", colors: [HubTheme.amber, .orange], size: 44, iconSize: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(light.name)
                                    .font(.headline)
                                Text("\(light.room) • \(light.ip)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $isOn)
                                .labelsHidden()
                                .tint(HubTheme.amber)
                                .onChange(of: isOn) { _, newVal in
                                    Task { await client.controlSmartLight(id: light.id, state: newVal) }
                                }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Helligkeit").font(.caption.bold()).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(brightness)) %").font(.caption.bold()).foregroundStyle(HubTheme.amber)
                            }
                            Slider(value: $brightness, in: 10...100, step: 5) { editing in
                                if !editing {
                                    isOn = true
                                    Task { await client.controlSmartLight(id: light.id, state: true, brightness: Int(brightness)) }
                                }
                            }
                            .tint(HubTheme.amber)
                        }
                    }
                    .padding(14)
                    .hubCard(cornerRadius: 18)

                    // White Temperature Presets
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WEISSTÖNE (FARBTEMPERATUR)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(tempPresets, id: \.1) { label, kelvin, col in
                                Button {
                                    isOn = true
                                    Task { await client.controlSmartLight(id: light.id, state: true, brightness: Int(brightness), tempK: kelvin) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Circle().fill(col).frame(width: 14, height: 14)
                                        Text(label).font(.system(size: 12, weight: .bold))
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(HubTheme.cardElevated, in: RoundedRectangle(cornerRadius: 11))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(14)
                    .hubCard(cornerRadius: 18)

                    // RGB Color Presets
                    VStack(alignment: .leading, spacing: 10) {
                        Text("VOLLFARBEN (RGB)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(colorPresets, id: \.0) { name, r, g, b, col in
                                Button {
                                    isOn = true
                                    Task { await client.controlSmartLight(id: light.id, state: true, brightness: Int(brightness), rgb: (r, g, b)) }
                                } label: {
                                    VStack(spacing: 6) {
                                        Circle()
                                            .fill(col)
                                            .frame(width: 28, height: 28)
                                            .shadow(color: col.opacity(0.6), radius: 6)
                                        Text(name)
                                            .font(.system(size: 11, weight: .bold))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(HubTheme.cardElevated, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(14)
                    .hubCard(cornerRadius: 18)

                    // Dynamic WiZ Scenes
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DYNAMISCHE WIZ LICHT-MODI")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(wizScenes, id: \.0) { sceneId, name, icon in
                                Button {
                                    isOn = true
                                    Task { await client.controlSmartLight(id: light.id, state: true, brightness: Int(brightness), sceneId: sceneId) }
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: icon)
                                            .foregroundStyle(HubTheme.sky)
                                        Text(name)
                                            .font(.system(size: 12.5, weight: .bold))
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(HubTheme.cardElevated, in: RoundedRectangle(cornerRadius: 11))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(14)
                    .hubCard(cornerRadius: 18)
                }
                .padding(14)
            }
            .background(HubTheme.bg.ignoresSafeArea())
            .navigationTitle(light.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear {
                isOn = light.isOn
                brightness = Double(light.brightness)
            }
        }
    }
}
