import SwiftUI
import Charts

enum SmartRoomFilter: String, CaseIterable, Identifiable {
    case all = "Alle"
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
    @State private var selectedPlugForChart: SmartPlugEnergyItem?
    @State private var selectedMedia: SmartMediaItem?

    @State private var masterBrightness: Double = 100
    @State private var rolloSlider: Double = 0
    @State private var isDraggingRollo = false
    @State private var tempSlider: Double = 21.5
    @State private var isDraggingTemp = false
    @State private var showPcStandbyConfirm = false

    private var state: SmartHomeStateResponse? { client.smartHomeState }

    private let lightQuickModes: [(String, String, Int?, Int?, Color)] = [
        ("Warmweiß", "sun.min.fill", nil, 2700, HubTheme.amber),
        ("Tageslicht", "sun.max.fill", nil, 5000, HubTheme.sky),
        ("Cozy", "flame.fill", 6, nil, .orange),
        ("Kamin", "fireplace.fill", 5, nil, HubTheme.rose),
        ("Sunset", "sun.haze.fill", 3, nil, HubTheme.pink),
        ("Ozean", "water.waves", 1, nil, HubTheme.sky),
        ("Party", "sparkles", 4, nil, HubTheme.purple),
        ("Nachtlicht", "moon.stars.fill", 14, nil, HubTheme.indigo)
    ]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 1. Non-clickable Security & Climate Status Strip (Door, Window, Temp, Power)
                    securityAndClimateStatusStrip

                    // 2. Room Filter Bar
                    roomFilterBar

                    // 3. Quick Scenes Carousel
                    scenesStrip

                    // 4. Wohnzimmer Beleuchtung (with built-in Light Mode Picker!)
                    if selectedRoom == .all || selectedRoom == .living {
                        lightingCardSection
                    }

                    // 5. Wohnzimmer Rollo (0-100% Flexible Slider) & Heizung (0.5°C Precision)
                    if selectedRoom == .all || selectedRoom == .living {
                        rolloControlCard
                        heatingControlCard
                    }

                    // 6. Refoss Smart Plugs with Live Watt & kWh Energy Monitoring
                    refossPlugsSection

                    // 7. Media, TV, Echo Show 5 & HomeServer PC
                    mediaAndPcSection

                    // 8. Smart Automations & Push Notifications (ntfy)
                    automationsSection
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 32)
            }
            .background(
                ZStack {
                    HubTheme.bg.ignoresSafeArea()
                    RadialGradient(
                        colors: [
                            (state?.summary.lightsOn ?? 0) > 0 ? HubTheme.amber.opacity(0.16) : HubTheme.sky.opacity(0.12),
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
                        Text(client.activeRouteLabel)
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
            .sheet(item: $selectedPlugForChart) { plug in
                PlugEnergyDetailSheet(plug: plug)
            }
            .sheet(item: $selectedMedia) { media in
                MediaPlayerDetailSheet(media: media)
            }
        }
        .task {
            await client.refreshSmartHome()
            syncSlidersFromState()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                await client.refreshSmartHome()
                syncSlidersFromState()
            }
        }
    }

    private func syncSlidersFromState() {
        if let firstB = state?.lights.first?.brightness {
            masterBrightness = Double(firstB)
        }
        if !isDraggingRollo, let pos = state?.cover.position {
            rolloSlider = Double(pos)
        }
        if !isDraggingTemp, let t = state?.climate.targetTemp {
            tempSlider = t
        }
    }

    // MARK: - 1. Security & Climate Status Strip (Non-Clickable Status Indicators!)

    private var securityAndClimateStatusStrip: some View {
        let sec = state?.security
        let doorOpen = sec?.doorOpen ?? false
        let winOpen = sec?.windowOpen ?? false
        let temp = sec?.currentTempC ?? 21.3
        let totalW = Int((state?.summary.powerWatts ?? 0).rounded())

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Non-clickable Door Sensor Badge
                statusIndicatorChip(
                    icon: doorOpen ? "door.left.hand.open" : "door.left.hand.closed",
                    title: "Wohnungstür",
                    value: doorOpen ? "GEÖFFNET ⚠️" : "Geschlossen",
                    color: doorOpen ? HubTheme.rose : HubTheme.emerald
                )

                // Non-clickable Window Sensor Badge
                statusIndicatorChip(
                    icon: winOpen ? "window.vertical.open" : "window.vertical.closed",
                    title: "Fenster",
                    value: winOpen ? "OFFEN ⚠️" : "Geschlossen",
                    color: winOpen ? HubTheme.amber : HubTheme.emerald
                )

                // Room Temperature Badge
                statusIndicatorChip(
                    icon: "thermometer.medium",
                    title: "Raumklima",
                    value: String(format: "%.1f °C", temp),
                    color: HubTheme.sky
                )

                // Total Power Badge
                statusIndicatorChip(
                    icon: "bolt.fill",
                    title: "Gesamt-Last",
                    value: "~\(totalW) W",
                    color: HubTheme.purple
                )
            }
        }
    }

    private func statusIndicatorChip(icon: String, title: String, value: String, color: Color) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .hubCard(cornerRadius: 18)
    }

    // MARK: - 2. Room Filter Bar

    private var roomFilterBar: some View {
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
                    .padding(.vertical, 8)
                    .background(isSel ? HubTheme.sky.opacity(0.22) : HubTheme.card, in: Capsule())
                    .overlay(Capsule().stroke(isSel ? HubTheme.sky.opacity(0.65) : HubTheme.border, lineWidth: 1))
                    .foregroundStyle(isSel ? .white : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 3. Quick Scenes Carousel

    private var scenesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                scenePill(id: "cozy", title: "Cozy Abend", icon: "flame.fill", colors: [HubTheme.amber, .orange])
                scenePill(id: "server", title: "Server-Modus", icon: "server.rack", colors: [HubTheme.emerald, .teal])
                scenePill(id: "gaming", title: "Gaming Vibe", icon: "gamecontroller.fill", colors: [HubTheme.pink, HubTheme.purple])
                scenePill(id: "bright", title: "Hell & Fokus", icon: "sun.max.fill", colors: [HubTheme.sky, HubTheme.emerald])
                scenePill(id: "cinema", title: "Kino & Rollo Zu", icon: "film.stack.fill", colors: [HubTheme.purple, HubTheme.indigo])
                scenePill(id: "all_off", title: "Lichter Aus", icon: "power", colors: [HubTheme.rose, .red])
            }
        }
    }

    private func scenePill(id: String, title: String, icon: String, colors: [Color]) -> some View {
        Button {
            Task { await client.triggerSmartScene(id) }
        } label: {
            HStack(spacing: 8) {
                IconBadge(symbol: icon, colors: colors, size: 30, iconSize: 13)
                Text(title)
                    .font(.system(size: 12.5, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .hubCard(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 4. Unified Lighting Section (with Built-in Mode Selector!)

    private var lightingCardSection: some View {
        let lights = state?.lights ?? []
        let anyOn = lights.contains(where: \.isOn)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconBadge(symbol: "lightbulb.2.fill", colors: [HubTheme.amber, .orange], size: 34, iconSize: 15)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Wohnzimmer Licht & Modi")
                        .font(.system(size: 14.5, weight: .heavy))
                    Text(anyOn ? "\(lights.filter(\.isOn).count) von \(lights.count) Lampen aktiv" : "Alle Lampen ausgeschaltet")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await client.controlSmartLight(id: "all", state: !anyOn) }
                } label: {
                    Text(anyOn ? "Alle Aus" : "Alle An")
                        .font(.system(size: 11.5, weight: .heavy))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(anyOn ? HubTheme.amber.opacity(0.22) : Color.white.opacity(0.08), in: Capsule())
                        .foregroundStyle(anyOn ? HubTheme.amber : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Quick Light Mode Selector Pills (1-Tap Mode Change for all Wohnzimmer lights!)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(lightQuickModes, id: \.0) { name, icon, sceneId, tempK, col in
                        let isCur = lights.first?.sceneName?.lowercased() == name.lowercased()
                        Button {
                            Task {
                                await client.controlSmartLight(
                                    id: "all",
                                    state: true,
                                    brightness: Int(masterBrightness),
                                    tempK: tempK,
                                    sceneId: sceneId
                                )
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: icon)
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(col)
                                Text(name)
                                    .font(.system(size: 11.5, weight: .bold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isCur ? col.opacity(0.22) : HubTheme.bg.opacity(0.6), in: Capsule())
                            .overlay(Capsule().stroke(isCur ? col.opacity(0.65) : HubTheme.border, lineWidth: 1))
                            .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Master Brightness Slider
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.caption)
                    .foregroundStyle(HubTheme.amber)
                Slider(value: $masterBrightness, in: 10...100, step: 5) { editing in
                    if !editing {
                        Task { await client.controlSmartLight(id: "all", state: true, brightness: Int(masterBrightness)) }
                    }
                }
                .tint(HubTheme.amber)
                Text("\(Int(masterBrightness))%")
                    .font(.system(size: 11.5, weight: .heavy, design: .monospaced))
                    .foregroundStyle(HubTheme.amber)
                    .frame(width: 38, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(HubTheme.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            // 3 Individual Light Tiles
            HStack(spacing: 8) {
                ForEach(lights) { light in
                    CompactLightTile(
                        light: light,
                        onToggle: {
                            Task { await client.controlSmartLight(id: light.id, state: !light.isOn) }
                        },
                        onOpenDetail: {
                            Haptics.light()
                            selectedLight = light
                        }
                    )
                }
            }
        }
        .padding(14)
        .hubCard(cornerRadius: 20, highlight: anyOn ? HubTheme.amber.opacity(0.45) : nil)
    }

    // MARK: - 5A. Flexible 0–100% Rollo Control Card (Aqara E1)

    private var rolloControlCard: some View {
        let cov = state?.cover
        let pos = Int(rolloSlider.rounded())
        let isOpen = pos > 3

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(
                    symbol: isOpen ? "blinds.horizontal.open" : "blinds.horizontal.closed",
                    colors: [HubTheme.sky, HubTheme.indigo],
                    size: 36,
                    iconSize: 16
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Wohnzimmer Rollo (Aqara E1)")
                        .font(.system(size: 14.5, weight: .heavy))
                    Text(pos == 0 ? "Komplett geschlossen (0%)" : (pos == 100 ? "Komplett geöffnet (100%)" : "Position: \(pos)% geöffnet"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(HubTheme.sky)
                }
                Spacer()
                Text("\(pos)%")
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundStyle(HubTheme.sky)
            }

            // Smooth 0%..100% Slider (every single percent!)
            HStack(spacing: 10) {
                Text("0%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Slider(
                    value: $rolloSlider,
                    in: 0...100,
                    step: 1,
                    onEditingChanged: { editing in
                        isDraggingRollo = editing
                        if !editing {
                            Task { await client.setCoverPosition(Int(rolloSlider.rounded())) }
                        }
                    }
                )
                .tint(HubTheme.sky)
                Text("100%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            // Quick Position Preset Buttons
            HStack(spacing: 6) {
                ForEach([("Zu (0%)", 0), ("25%", 25), ("50%", 50), ("75%", 75), ("Auf (100%)", 100)], id: \.1) { lbl, targetPos in
                    Button {
                        rolloSlider = Double(targetPos)
                        Task { await client.setCoverPosition(targetPos) }
                    } label: {
                        Text(lbl)
                            .font(.system(size: 11, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(abs(pos - targetPos) <= 2 ? HubTheme.sky.opacity(0.25) : HubTheme.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(abs(pos - targetPos) <= 2 ? HubTheme.sky : HubTheme.border, lineWidth: 1))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    Task { await client.triggerCoverAction("stop") }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(HubTheme.rose.opacity(0.2), in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(HubTheme.rose)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .hubCard(cornerRadius: 20)
    }

    // MARK: - 5B. Flexible Heating / Thermostat Control Card (Kasa KE100)

    private var heatingControlCard: some View {
        let cl = state?.climate
        let isHeating = cl?.isHeating ?? false
        let curT = cl?.currentTemp ?? 21.3

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(
                    symbol: isHeating ? "flame.fill" : "snowflake",
                    colors: isHeating ? [HubTheme.amber, HubTheme.rose] : [.gray, HubTheme.sky],
                    size: 36,
                    iconSize: 16
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Wohnzimmer Heizung (Thermostat)")
                        .font(.system(size: 14.5, weight: .heavy))
                    Text(String(format: "Ist-Temperatur: %.1f °C • %@", curT, isHeating ? "Heizt aktiv" : "Ausgeschaltet"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isHeating ? HubTheme.amber : .secondary)
                }
                Spacer()
                Button {
                    Task { await client.setClimate(hvacMode: isHeating ? "off" : "heat") }
                } label: {
                    Text(isHeating ? "HEIZT" : "AUS")
                        .font(.system(size: 11, weight: .heavy))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background((isHeating ? HubTheme.amber : Color.white).opacity(0.18), in: Capsule())
                        .foregroundStyle(isHeating ? HubTheme.amber : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Target Temperature Stepper + Slider (5.0°C .. 30.0°C in 0.5°C steps)
            HStack(spacing: 10) {
                Button {
                    let next = max(5.0, (tempSlider * 2.0).rounded() / 2.0 - 0.5)
                    tempSlider = next
                    Task { await client.setClimate(hvacMode: "heat", targetTemp: next) }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(HubTheme.cardElevated, in: Circle())
                }
                .buttonStyle(.plain)

                Slider(
                    value: $tempSlider,
                    in: 5.0...30.0,
                    step: 0.5,
                    onEditingChanged: { editing in
                        isDraggingTemp = editing
                        if !editing {
                            Task { await client.setClimate(hvacMode: "heat", targetTemp: tempSlider) }
                        }
                    }
                )
                .tint(HubTheme.amber)

                Button {
                    let next = min(30.0, (tempSlider * 2.0).rounded() / 2.0 + 0.5)
                    tempSlider = next
                    Task { await client.setClimate(hvacMode: "heat", targetTemp: next) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(HubTheme.cardElevated, in: Circle())
                }
                .buttonStyle(.plain)

                Text(String(format: "%.1f°C", tempSlider))
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundStyle(HubTheme.amber)
                    .frame(width: 56, alignment: .trailing)
            }

            // Quick Temperature Presets
            HStack(spacing: 8) {
                ForEach([("Eco 18°C", 18.0), ("Komfort 21,5°C", 21.5), ("Warm 23,5°C", 23.5)], id: \.0) { lbl, val in
                    Button {
                        tempSlider = val
                        Task { await client.setClimate(hvacMode: "heat", targetTemp: val) }
                    } label: {
                        Text(lbl)
                            .font(.system(size: 11, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(abs(tempSlider - val) < 0.2 ? HubTheme.amber.opacity(0.22) : HubTheme.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(abs(tempSlider - val) < 0.2 ? HubTheme.amber : HubTheme.border, lineWidth: 1))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .hubCard(cornerRadius: 20)
    }

    // MARK: - 6. Refoss Smart Plugs with Live Watt & kWh Energy Monitoring

    private var refossPlugsSection: some View {
        let allPlugs = state?.plugs ?? []
        let filtered = selectedRoom == .all ? allPlugs : allPlugs.filter { $0.room.lowercased() == selectedRoom.rawValue.lowercased() }

        return Group {
            if !filtered.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Refoss Steckdosen & Strommessung", systemImage: "powerplug.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "Monat: %.2f kWh", state?.summary.monthKwh ?? 0))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(HubTheme.emerald)
                    }
                    .padding(.horizontal, 4)

                    let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(filtered) { plug in
                            RefossPlugCard(
                                plug: plug,
                                onToggle: {
                                    Task { await client.toggleSmartPlug(plug) }
                                },
                                onOpenChart: {
                                    Haptics.light()
                                    selectedPlugForChart = plug
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - 7. Media, TV, Echo Show 5 & Dedicated HomeServer PC Dual-Mode Card

    private var mediaAndPcSection: some View {
        let allMedia = state?.mediaPlayers ?? []
        let filteredMedia = selectedRoom == .all ? allMedia : allMedia.filter { $0.room.lowercased() == selectedRoom.rawValue.lowercased() }
        let sec = state?.security

        return VStack(alignment: .leading, spacing: 14) {
            if !filteredMedia.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Media & Audio (AirPlay / Cast / Echo)", systemImage: "tv.and.hifispeaker.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)

                    let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                    LazyVGrid(columns: cols, spacing: 10) {
                        ForEach(filteredMedia) { media in
                            Button {
                                Haptics.light()
                                selectedMedia = media
                            } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        IconBadge(
                                            symbol: media.icon,
                                            colors: media.isOn ? [HubTheme.purple, HubTheme.sky] : [.gray, .gray.opacity(0.6)],
                                            size: 36,
                                            iconSize: 16
                                        )
                                        Spacer()
                                        StatusBadgePill(
                                            text: media.isPlaying ? "SPIELT" : (media.isOn ? "BEREIT" : "STANDBY"),
                                            active: media.isOn,
                                            activeColor: media.isPlaying ? HubTheme.emerald : HubTheme.sky
                                        )
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(media.name)
                                            .font(.system(size: 13, weight: .heavy))
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                        Text(media.subtitle)
                                            .font(.system(size: 10.5))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .padding(12)
                                .hubCard(cornerRadius: 18, highlight: media.isPlaying ? HubTheme.purple : nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Dedicated HomeServer PC Card with Dual-Mode Switcher (HomeServer vs Gaming)
            if selectedRoom == .all || selectedRoom == .living {
                homeServerPcControlCard(sec: sec)
            }
        }
    }

    private func homeServerPcControlCard(sec: SmartSecurityStatus?) -> some View {
        let pcOn = sec?.pcOnline ?? false
        let isServer = (sec?.pcMode ?? "").lowercased().contains("server") || (sec?.pcMode == nil)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(
                    symbol: "desktopcomputer",
                    colors: pcOn ? (isServer ? [HubTheme.emerald, .teal] : [HubTheme.pink, HubTheme.purple]) : [.gray, .gray.opacity(0.6)],
                    size: 38,
                    iconSize: 18
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("HomeServer PC")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(.white)
                        if pcOn {
                            Circle()
                                .fill(isServer ? HubTheme.emerald : HubTheme.pink)
                                .frame(width: 7, height: 7)
                        }
                    }
                    Text(pcOn ? (isServer ? "⚡ Server-Modus aktiv (Dienste laufen)" : "🎮 Gaming-Modus aktiv (Max FPS)") : "0W Ausgeschaltet (Ruhezustand)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(pcOn ? (isServer ? HubTheme.emerald : HubTheme.pink) : .secondary)
                }
                Spacer()
                StatusBadgePill(text: pcOn ? "~\(sec?.pcWatts ?? 115) W" : "0W AUS", active: pcOn)
            }

            if pcOn {
                // Interactive Mode Switcher Row: Server vs Gaming
                HStack(spacing: 8) {
                    Button {
                        Task { await client.setPcMode(serverMode: true) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("⚡ Server-Modus")
                                .font(.system(size: 12, weight: .heavy))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(isServer ? LinearGradient(colors: [HubTheme.emerald, Color.teal], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.06)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(isServer ? HubTheme.emerald.opacity(0.8) : HubTheme.border, lineWidth: 1))
                        .foregroundStyle(isServer ? .white : .secondary)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await client.setPcMode(serverMode: false) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("🎮 Gaming-Modus")
                                .font(.system(size: 12, weight: .heavy))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(!isServer ? LinearGradient(colors: [HubTheme.pink, HubTheme.purple], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.06)], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(!isServer ? HubTheme.pink.opacity(0.8) : HubTheme.border, lineWidth: 1))
                        .foregroundStyle(!isServer ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }

                // 0W Standby Action
                Button {
                    showPcStandbyConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "powersleep")
                            .font(.system(size: 11))
                        Text("In 0W Ruhezustand versetzen")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
                .confirmationDialog("PC in Ruhezustand?", isPresented: $showPcStandbyConfirm, titleVisibility: .visible) {
                    Button("💤 0W Ruhezustand aktivieren", role: .destructive) {
                        Task { await client.shutdownPc() }
                    }
                    Button("Abbrechen", role: .cancel) {}
                } message: {
                    Text("Der PC wechselt in den 0-Watt Energiesparmodus. Dienste werden pausiert. Kann jederzeit über Wake-on-LAN geweckt werden.")
                }
            } else {
                Button {
                    Task { await client.wakePc() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("⚡ PC Aufwecken (Wake-on-LAN)")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(LinearGradient(colors: [HubTheme.emerald, Color.teal], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .hubCard(cornerRadius: 20, highlight: pcOn ? (isServer ? HubTheme.emerald.opacity(0.35) : HubTheme.pink.opacity(0.35)) : nil)
    }

    // MARK: - 8. Smart Automations & Native Push Mitteilungen

    private var automationsSection: some View {
        let autos = state?.automations ?? []
        return Group {
            if !autos.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("Smarte Automationen & Mitteilungen", systemImage: "bell.badge.waveform.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Nativ auf iPhone")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(HubTheme.emerald)
                    }
                    .padding(.horizontal, 4)

                    VStack(spacing: 8) {
                        ForEach(autos) { auto in
                            HStack(spacing: 12) {
                                IconBadge(
                                    symbol: auto.icon,
                                    colors: auto.isEnabled ? [HubTheme.indigo, HubTheme.sky] : [.gray, .gray.opacity(0.6)],
                                    size: 34,
                                    iconSize: 15
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(auto.name)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text(auto.subtitle)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: { auto.isEnabled },
                                    set: { newVal in
                                        Task { await client.toggleAutomation(id: auto.id, enabled: newVal) }
                                    }
                                ))
                                .labelsHidden()
                                .tint(HubTheme.emerald)
                            }
                            .padding(11)
                            .hubCard(cornerRadius: 16)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Subcomponents

private struct CompactLightTile: View {
    let light: SmartLightItem
    let onToggle: () -> Void
    let onOpenDetail: () -> Void

    private var lampIcon: String {
        if light.name.contains("2") || light.id.contains("2") {
            return light.isOn ? "lamp.desk.fill" : "lamp.desk"
        }
        return light.isOn ? "lightbulb.fill" : "lightbulb"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: onToggle) {
                    ZStack {
                        Circle()
                            .fill(light.isOn ? light.accentColor.opacity(0.28) : Color.white.opacity(0.06))
                            .frame(width: 34, height: 34)
                        Image(systemName: lampIcon)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(light.isOn ? light.accentColor : .secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onOpenDetail) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10.5, weight: .bold))
                        .padding(6)
                        .background(Color.white.opacity(0.07), in: Circle())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(light.name.replacingOccurrences(of: "Wohnzimmer ", with: ""))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(light.isOn ? .white : .secondary)
                        .lineLimit(1)
                    Text(light.isOn ? "\(light.brightness)% • \(light.sceneName ?? "An")" : "Aus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(light.isOn ? light.accentColor : .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(HubTheme.bg.opacity(0.65), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(light.isOn ? light.accentColor.opacity(0.5) : HubTheme.border, lineWidth: 1))
    }
}

private struct RefossPlugCard: View {
    let plug: SmartPlugEnergyItem
    let onToggle: () -> Void
    let onOpenChart: () -> Void

    private var resolvedIcon: String {
        if !plug.icon.isEmpty && plug.icon != "powerplug" {
            return plug.icon
        }
        if plug.name.lowercased().contains("wasch") { return "washer.fill" }
        if plug.name.lowercased().contains("lampe") || plug.id.contains("schreibtisch") { return "lamp.desk.fill" }
        if plug.name.lowercased().contains("led") { return "light.strip.2.fill" }
        return "powerplug.fill"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: onToggle) {
                    ZStack {
                        Circle()
                            .fill(plug.isOn ? HubTheme.emerald.opacity(0.25) : Color.white.opacity(0.06))
                            .frame(width: 38, height: 38)
                        Image(systemName: resolvedIcon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(plug.isOn ? HubTheme.emerald : .secondary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onOpenChart) {
                    HStack(spacing: 3) {
                        Image(systemName: "chart.bar.xaxis")
                        Text(String(format: "%.2f kWh", plug.monthKwh))
                    }
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(HubTheme.sky.opacity(0.16), in: Capsule())
                    .foregroundStyle(HubTheme.sky)
                }
                .buttonStyle(.plain)
            }

            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(plug.name.replacingOccurrences(of: "Refoss ", with: ""))
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(plug.isOn ? "AN" : "AUS")
                            .font(.system(size: 10.5, weight: .heavy))
                            .foregroundStyle(plug.isOn ? HubTheme.emerald : .secondary)
                        Text("• \(String(format: "%.1f W", plug.powerW)) • Heute \(plug.todayWh) Wh")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .hubCard(cornerRadius: 18, highlight: plug.isOn ? HubTheme.emerald.opacity(0.55) : nil)
    }
}

// MARK: - Refoss 14-Day Energy Chart Sheet

struct PlugEnergyDetailSheet: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.dismiss) private var dismiss
    let plug: SmartPlugEnergyItem

    @State private var liveWattSamples: [Double] = []

    private var livePlug: SmartPlugEnergyItem {
        client.smartHomeState?.plugs.first(where: { $0.id == plug.id }) ?? plug
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 12) {
                        IconBadge(symbol: livePlug.icon, colors: [HubTheme.emerald, HubTheme.sky], size: 44, iconSize: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(livePlug.name)
                                .font(.headline)
                            Text("\(livePlug.room) • \(livePlug.ip) • \(String(format: "%.1f V", livePlug.voltageV))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await client.toggleSmartPlug(livePlug) }
                        } label: {
                            Text(livePlug.isOn ? "Ausschalten" : "Einschalten")
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(livePlug.isOn ? HubTheme.emerald : HubTheme.cardElevated, in: Capsule())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .hubCard(cornerRadius: 18)

                    HStack(spacing: 10) {
                        kpiBox(title: "AKTUELL", val: String(format: "%.1f W", livePlug.powerW), color: HubTheme.amber)
                        kpiBox(title: "HEUTE", val: "\(livePlug.todayWh) Wh", color: HubTheme.sky)
                        kpiBox(title: "30 TAGE", val: String(format: "%.2f kWh", livePlug.monthKwh), color: HubTheme.emerald)
                    }

                    // Live Watt Sparkline while sheet is open
                    if liveWattSamples.count >= 2 {
                        let indexed = Array(liveWattSamples.enumerated())
                        let minW = max(0.0, (liveWattSamples.min() ?? 0.0) - 2.0)
                        let maxW = max(minW + 5.0, (liveWattSamples.max() ?? 10.0) + 2.0)

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("LIVE STROMVERLAUF (WATT)")
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "Live: %.1f W", livePlug.powerW))
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(HubTheme.amber)
                            }
                            Chart {
                                ForEach(indexed, id: \.offset) { idx, wVal in
                                    AreaMark(
                                        x: .value("T", idx),
                                        yStart: .value("Base", minW),
                                        yEnd: .value("W", wVal)
                                    )
                                    .foregroundStyle(LinearGradient(colors: [HubTheme.amber.opacity(0.38), .clear], startPoint: .top, endPoint: .bottom))
                                    .interpolationMethod(.catmullRom)

                                    LineMark(x: .value("T", idx), y: .value("W", wVal))
                                        .foregroundStyle(HubTheme.amber)
                                        .lineStyle(StrokeStyle(lineWidth: 2.2))
                                        .interpolationMethod(.catmullRom)
                                }
                            }
                            .chartXScale(domain: 0...max(1, indexed.count - 1))
                            .chartYScale(domain: minW...maxW)
                            .chartXAxis(.hidden)
                            .frame(height: 110)
                        }
                        .padding(14)
                        .hubCard(cornerRadius: 18)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("TÄGLICHER STROMVERBRAUCH (14 TAGE IN WH)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(.secondary)

                        if livePlug.history.isEmpty {
                            Text("Noch keine Verbrauchsdaten aufgezeichnet.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 20)
                        } else {
                            Chart(livePlug.history) { item in
                                BarMark(
                                    x: .value("Tag", String(item.date.suffix(5))),
                                    y: .value("Wh", item.wh)
                                )
                                .foregroundStyle(LinearGradient(colors: [HubTheme.sky, HubTheme.emerald], startPoint: .top, endPoint: .bottom))
                                .cornerRadius(4)
                            }
                            .frame(height: 190)
                        }
                    }
                    .padding(14)
                    .hubCard(cornerRadius: 18)
                }
                .padding(14)
            }
            .background(HubTheme.bg.ignoresSafeArea())
            .navigationTitle("Strommessung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .task {
                liveWattSamples = [livePlug.powerW, livePlug.powerW]
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    await client.refreshSmartHome()
                    liveWattSamples.append(livePlug.powerW)
                    if liveWattSamples.count > 30 {
                        liveWattSamples.removeFirst()
                    }
                }
            }
        }
    }

    private func kpiBox(title: String, val: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.system(size: 9.5, weight: .heavy)).foregroundStyle(.secondary)
            Text(val).font(.system(size: 16, weight: .heavy)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .hubCard(cornerRadius: 14)
    }
}

// MARK: - Media & TV Control Sheet (HomePod, Echo Show 5, Chromecast HD, LG TV)

struct MediaPlayerDetailSheet: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.dismiss) private var dismiss
    let media: SmartMediaItem

    @State private var volume: Double = 50

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    IconBadge(symbol: media.icon, colors: [HubTheme.purple, HubTheme.sky], size: 48, iconSize: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(media.name)
                            .font(.headline)
                        Text("\(media.brand) • \(media.room)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(media.subtitle)
                            .font(.caption.bold())
                            .foregroundStyle(HubTheme.sky)
                    }
                    Spacer()
                }
                .padding(16)
                .hubCard(cornerRadius: 18)

                // Playback & Power Controls
                HStack(spacing: 14) {
                    Button {
                        Task { await client.controlMediaPlayer(id: media.id, haEntityId: media.haEntityId, action: "previous") }
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.title3.bold())
                            .frame(width: 54, height: 54)
                            .background(HubTheme.cardElevated, in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await client.controlMediaPlayer(id: media.id, haEntityId: media.haEntityId, action: "play_pause") }
                    } label: {
                        Image(systemName: media.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2.bold())
                            .frame(width: 68, height: 68)
                            .background(LinearGradient(colors: [HubTheme.purple, HubTheme.sky], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await client.controlMediaPlayer(id: media.id, haEntityId: media.haEntityId, action: "next") }
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.title3.bold())
                            .frame(width: 54, height: 54)
                            .background(HubTheme.cardElevated, in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                // Volume Slider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Lautstärke", systemImage: "speaker.wave.2.fill")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(volume)) %")
                            .font(.caption.bold())
                            .foregroundStyle(HubTheme.sky)
                    }
                    Slider(value: $volume, in: 0...100, step: 5) { editing in
                        if !editing {
                            Task { await client.controlMediaPlayer(id: media.id, haEntityId: media.haEntityId, action: "volume", volumePct: Int(volume)) }
                        }
                    }
                    .tint(HubTheme.sky)
                }
                .padding(14)
                .hubCard(cornerRadius: 18)

                // Device Specific Actions (Echo Show Dashboard or TV Power)
                if media.id == "echo_show_5" {
                    Button {
                        Task { await client.controlMediaPlayer(id: media.id, haEntityId: media.haEntityId, action: "echo_dashboard") }
                    } label: {
                        Label("Smart-Home-Dashboard auf Echo Show 5 öffnen", systemImage: "rectangle.grid.2x2.fill")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(HubTheme.emerald, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            Task { await client.controlMediaPlayer(id: media.id, haEntityId: media.haEntityId, action: "turn_on") }
                        } label: {
                            Label("Einschalten / Wecken", systemImage: "power")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(HubTheme.emerald.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(HubTheme.emerald)
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await client.controlMediaPlayer(id: media.id, haEntityId: media.haEntityId, action: "turn_off") }
                        } label: {
                            Label("Standby / Aus", systemImage: "powersleep")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(HubTheme.rose.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(HubTheme.rose)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding(16)
            .background(HubTheme.bg.ignoresSafeArea())
            .navigationTitle(media.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear {
                volume = Double(media.volumePct)
            }
        }
        .presentationDetents([.medium])
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
