import SwiftUI

struct DeviceManagerTabView: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.openURL) private var openURL

    @State private var showQuickAdd = false
    @State private var deleteTargetIndex: Int?
    @State private var deleteTargetName: String = ""

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // Header Banner
                    HStack(spacing: 12) {
                        IconBadge(symbol: "slider.horizontal.below.rectangle", colors: [HubTheme.emerald, HubTheme.sky], size: 42, iconSize: 19)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Überwachte Geräte & Preisspannen")
                                .font(.system(size: 15, weight: .heavy))
                            Text("Ändere Min/Max-Preise direkt oder füge neue Suchaufträge hinzu.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .hubCard(cornerRadius: 18)

                    // Add New Device Button
                    Button {
                        Haptics.light()
                        showQuickAdd = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3.bold())
                            Text("Neues Gerät zur Überwachung hinzufügen")
                                .font(.system(size: 14, weight: .heavy))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(LinearGradient(colors: [HubTheme.emerald, .teal], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.white)
                        .shadow(color: HubTheme.emerald.opacity(0.3), radius: 10, y: 4)
                    }
                    .buttonStyle(.plain)

                    // List of Device Cards
                    if let searches = client.dealConfig?.searches, !searches.isEmpty {
                        ForEach(Array(searches.enumerated()), id: \.offset) { idx, rule in
                            DeviceRuleCard(
                                index: idx,
                                rule: rule,
                                onSavePrice: { minP, maxP in
                                    Task {
                                        _ = await client.updateQuickPrice(index: idx, minPrice: minP, maxPrice: maxP)
                                        await client.refreshDealState()
                                    }
                                },
                                onToggleEnabled: { newVal in
                                    Task {
                                        guard var cfg = client.dealConfig, idx < cfg.searches.count else { return }
                                        cfg.searches[idx].enabled = newVal
                                        if await client.saveDealConfig(cfg) {
                                            client.showToast(newVal ? "▶ \(rule.name) aktiviert" : "⏸ \(rule.name) pausiert")
                                            await client.refreshDealState()
                                        }
                                    }
                                },
                                onDeepScan: {
                                    Task {
                                        await client.triggerDealScan(deep: true, searchName: rule.name)
                                    }
                                },
                                onOpenURL: {
                                    if let u = URL(string: rule.url) { openURL(u) }
                                },
                                onDelete: {
                                    Haptics.warning()
                                    deleteTargetIndex = idx
                                    deleteTargetName = rule.name
                                }
                            )
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass.circle.fill")
                                .font(.system(size: 38))
                                .foregroundStyle(HubTheme.sky)
                            Text("Keine Geräte geladen")
                                .font(.headline)
                            Text("Ziehe nach unten zum Aktualisieren oder füge oben ein neues Gerät hinzu.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                        .hubCard(cornerRadius: 18)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .background(HubTheme.bg.ignoresSafeArea())
            .navigationTitle("Geräte & Preise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        showQuickAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                            .foregroundStyle(HubTheme.emerald)
                    }
                }
            }
            .refreshable {
                await client.fetchDealConfig()
                await client.refreshDealState()
            }
            .task {
                await client.fetchDealConfig()
            }
            .sheet(isPresented: $showQuickAdd) {
                QuickAddDeviceSheet(onSaved: {
                    Task {
                        await client.fetchDealConfig()
                        await client.refreshDealState()
                    }
                })
            }
            .confirmationDialog(
                "🗑 \"\(deleteTargetName)\" entfernen?",
                isPresented: Binding(
                    get: { deleteTargetIndex != nil },
                    set: { if !$0 { deleteTargetIndex = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Nur Überwachung löschen", role: .destructive) {
                    if let idx = deleteTargetIndex {
                        Task { _ = await client.deleteSearchRule(index: idx, deleteAds: false) }
                    }
                }
                Button("Gerät + alle gespeicherten Deals löschen", role: .destructive) {
                    if let idx = deleteTargetIndex {
                        Task { _ = await client.deleteSearchRule(index: idx, deleteAds: true) }
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Das Gerät wird sofort aus deiner Pi-Konfiguration gelöscht und nicht mehr gescannt.")
            }
        }
    }
}

private struct DeviceRuleCard: View {
    let index: Int
    let rule: SearchRule
    let onSavePrice: (Double, Double) -> Void
    let onToggleEnabled: (Bool) -> Void
    let onDeepScan: () -> Void
    let onOpenURL: () -> Void
    let onDelete: () -> Void

    @State private var minVal: Int = 0
    @State private var maxVal: Int = 500
    @State private var isOn: Bool = true

    private var deviceSymbol: String {
        let low = rule.name.lowercased()
        if low.contains("iphone") || low.contains("pixel") || low.contains("galaxy") { return "iphone" }
        if low.contains("ipad") || low.contains("tablet") { return "ipad" }
        if low.contains("macbook") || low.contains("thinkpad") || low.contains("laptop") { return "laptopcomputer" }
        if low.contains("switch") || low.contains("steam") || low.contains("ps5") || low.contains("playstation") { return "gamecontroller.fill" }
        if low.contains("rtx") || low.contains("gpu") || low.contains("rx ") { return "cpu.fill" }
        return "tag.fill"
    }

    private var badgeColors: [Color] {
        if !isOn { return [.gray, .gray.opacity(0.6)] }
        if rule.conditionMode == "defective_only" { return [HubTheme.amber, HubTheme.rose] }
        return [HubTheme.sky, HubTheme.indigo]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(symbol: deviceSymbol, colors: badgeColors, size: 38, iconSize: 17)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name)
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(isOn ? .white : .secondary)
                    HStack(spacing: 6) {
                        Text(rule.conditionMode == "defective_only" ? "🔧 Defekt / Bastler" : (rule.conditionMode == "any" ? "🎯 Alle Zustände" : "✅ Funktionierend"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(rule.conditionMode == "defective_only" ? HubTheme.amber : HubTheme.emerald)
                        Text("• \(minVal)–\(maxVal) €")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(HubTheme.sky)
                    }
                }

                Spacer()

                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(HubTheme.emerald)
                    .onChange(of: isOn) { _, newVal in
                        if newVal != rule.isEnabled {
                            onToggleEnabled(newVal)
                        }
                    }
            }

            // Quick Price Editor Row with +/- Steppers & Direct Number Input
            HStack(spacing: 8) {
                priceBox(title: "MIN €", value: $minVal, step: 10)
                priceBox(title: "MAX €", value: $maxVal, step: 10)

                Button {
                    Haptics.medium()
                    onSavePrice(Double(minVal), Double(maxVal))
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                        Text("Speichern")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .frame(width: 74, height: 48)
                    .background(LinearGradient(colors: [HubTheme.sky, HubTheme.indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            // Bottom Action Bar
            HStack(spacing: 8) {
                Button {
                    onDeepScan()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkle.magnifyingglass")
                        Text("Alle Seiten scannen")
                    }
                    .font(.system(size: 11.5, weight: .bold))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(HubTheme.indigo.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(HubTheme.indigo.opacity(0.5), lineWidth: 1))
                    .foregroundStyle(Color(red: 0.78, green: 0.82, blue: 1.0))
                }
                .buttonStyle(.plain)

                Button {
                    onOpenURL()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "safari")
                        Text("Link")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    onDelete()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash.fill")
                        Text("Löschen")
                    }
                    .font(.system(size: 11.5, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(HubTheme.rose.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(HubTheme.rose.opacity(0.45), lineWidth: 1))
                    .foregroundStyle(HubTheme.rose)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .hubCard(cornerRadius: 18, highlight: isOn ? nil : .gray.opacity(0.2))
        .onAppear {
            minVal = Int((rule.minPrice ?? 0).rounded())
            maxVal = Int((rule.maxPrice ?? 500).rounded())
            isOn = rule.isEnabled
        }
    }

    private func priceBox(title: String, value: Binding<Int>, step: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Button {
                    Haptics.light()
                    value.wrappedValue = max(0, value.wrappedValue - step)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 26)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                TextField("0", value: value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13.5, weight: .heavy))
                    .frame(maxWidth: .infinity)

                Button {
                    Haptics.light()
                    value.wrappedValue += step
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 26)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(HubTheme.bg.opacity(0.65), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(HubTheme.border, lineWidth: 1))
    }
}

struct QuickAddDeviceSheet: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let onSaved: () -> Void

    @State private var query = ""
    @State private var customName = ""
    @State private var minPrice = 50
    @State private var maxPrice = 350
    @State private var radiusKm = 75
    @State private var category = "all"
    @State private var conditionMode = "working_only"
    @State private var requiredCsv = ""
    @State private var extraNegCsv = ""
    @State private var ignoreCommercial = false
    @State private var runDeepScan = true
    @State private var previewURL = ""
    @State private var isSaving = false

    private let radii = [
        (20, "20 km"), (50, "50 km"), (75, "75 km (FFM)"), (100, "100 km"),
        (150, "150 km"), (200, "200 km"), (0, "Deutschlandweit")
    ]

    private let categories = [
        ("all", "Alle Kategorien"), ("electronics", "Elektronik"),
        ("notebooks", "Notebooks / MacBooks"), ("consoles", "Konsolen"),
        ("phones", "Handy & Telefon"), ("tablets", "Tablets & iPads"),
        ("pcs", "PCs"), ("hardware", "PC-Hardware / GPUs"), ("cameras", "Foto & Kameras")
    ]

    private let defaultNegWorking = [
        "defekt","defekte","defekter","defektes","kaputt","kaputte","kaputter","bastler",
        "ersatzteil","ersatzteile","schaden","glasbruch","displaybruch","wasserschaden",
        "icloud","gesperrt","aktivierungssperre","ohne funktion","geht nicht an",
        "suche","suchauftrag","ankauf","tausch","tausche","tauschen",
        "nur ovp","nur karton","leerkarton","reparaturservice"
    ]

    private let defaultNegDefective = [
        "icloud","gesperrt","aktivierungssperre","mdm","passwort vergessen",
        "suche","suchauftrag","ankauf","tausch","tausche","reparaturservice",
        "nur ovp","nur karton","leerkarton","hülle","tasche","netzteil","ladekabel"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Schnell-Vorlagen (1-Tap)") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            presetBtn("📱 iPhone", q: "iPhone 15", min: 150, max: 480, r: 75, c: "phones", neg: "hülle, case, panzerglas, folie")
                            presetBtn("💻 MacBook", q: "MacBook Air M1", min: 150, max: 450, r: 75, c: "notebooks", neg: "hülle, tasche, netzteil")
                            presetBtn("🕹️ Steam Deck", q: "Steam Deck", min: 180, max: 380, r: 100, c: "consoles", neg: "tasche, dock, hülle")
                            presetBtn("🎮 Switch OLED", q: "Nintendo Switch OLED", min: 100, max: 210, r: 75, c: "consoles", neg: "tasche, spiel, controller")
                            presetBtn("📟 iPad Pro", q: "iPad Pro", min: 120, max: 400, r: 75, c: "tablets", neg: "hülle, tastatur, pencil")
                            presetBtn("🖥️ RTX GPU", q: "RTX 4070", min: 250, max: 450, r: 100, c: "hardware", neg: "kühler, wasserblock, lüfter")
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Gerät & Preisspanne") {
                    TextField("Suchbegriff (z. B. Steam Deck OLED)", text: $query)
                        .autocorrectionDisabled()
                    HStack {
                        Text("Min (€)")
                        Spacer()
                        TextField("Min", value: $minPrice, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    HStack {
                        Text("Max (€)")
                        Spacer()
                        TextField("Max", value: $maxPrice, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    Picker("Umkreis", selection: $radiusKm) {
                        ForEach(radii, id: \.0) { r, lbl in Text(lbl).tag(r) }
                    }
                    Picker("Kategorie", selection: $category) {
                        ForEach(categories, id: \.0) { c, lbl in Text(lbl).tag(c) }
                    }
                }

                Section("Zustands-Filter") {
                    Picker("Modus", selection: $conditionMode) {
                        Text("✅ Funktionierend").tag("working_only")
                        Text("🔧 Defekt / Bastler").tag("defective_only")
                        Text("🎯 Alle").tag("any")
                    }
                    .pickerStyle(.segmented)
                    Toggle("Gewerbliche (PRO) ausblenden", isOn: $ignoreCommercial)
                }

                Section("Optional: Feintuning") {
                    TextField("Eigener Name (optional)", text: $customName)
                    TextField("Pflicht-Keywords (kommagetrennt)", text: $requiredCsv)
                    TextField("Extra Ausschluss-Keywords", text: $extraNegCsv)
                }

                if !previewURL.isEmpty {
                    Section("Generierte Kleinanzeigen-URL") {
                        Text(previewURL)
                            .font(.caption2.monospaced())
                            .foregroundStyle(HubTheme.sky)
                        Button {
                            if let u = URL(string: previewURL) { openURL(u) }
                        } label: {
                            Label("In Safari testen", systemImage: "safari")
                        }
                    }
                }

                Section {
                    Toggle("🔎 Direkt alle Seiten nach Schätzen scannen", isOn: $runDeepScan)
                }
            }
            .navigationTitle("Neues Gerät")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Anlegen") {
                        Task { await save() }
                    }
                    .bold()
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onChange(of: query) { _, _ in refreshPreview() }
            .onChange(of: minPrice) { _, _ in refreshPreview() }
            .onChange(of: maxPrice) { _, _ in refreshPreview() }
            .onChange(of: radiusKm) { _, _ in refreshPreview() }
            .onChange(of: category) { _, _ in refreshPreview() }
        }
    }

    private func presetBtn(_ label: String, q: String, min: Int, max: Int, r: Int, c: String, neg: String) -> some View {
        Button(label) {
            Haptics.light()
            query = q; minPrice = min; maxPrice = max; radiusKm = r; category = c; extraNegCsv = neg; conditionMode = "working_only"
            refreshPreview()
        }
        .buttonStyle(.bordered)
        .font(.caption.weight(.semibold))
    }

    private func refreshPreview() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { previewURL = ""; return }
        Task {
            if let url = await client.buildKleinanzeigenURL(query: trimmed, minPrice: minPrice, maxPrice: maxPrice, radiusKm: radiusKm, category: category) {
                previewURL = url
            }
        }
    }

    private func splitCsv(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func save() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        if client.dealConfig == nil { await client.fetchDealConfig() }
        guard var cfg = client.dealConfig else {
            client.showToast("Konnte Config nicht laden")
            return
        }
        guard let url = await client.buildKleinanzeigenURL(query: trimmed, minPrice: minPrice, maxPrice: maxPrice, radiusKm: radiusKm, category: category) else {
            client.showToast("URL-Erstellung fehlgeschlagen")
            return
        }

        let radLabel = radiusKm > 0 ? " (\(radiusKm) km)" : " (DE)"
        let modeSuffix = conditionMode == "defective_only" ? " Defekt" : ""
        let finalName = customName.trimmingCharacters(in: .whitespaces).isEmpty ? "\(trimmed)\(modeSuffix)\(radLabel)" : customName.trimmingCharacters(in: .whitespaces)

        let baseNeg: [String] = {
            switch conditionMode {
            case "working_only": return defaultNegWorking
            case "defective_only": return defaultNegDefective
            default: return ["suche", "suchauftrag", "ankauf", "tausch", "tausche", "nur ovp", "leerkarton"]
            }
        }()
        let combinedNeg = Array(Set(baseNeg + splitCsv(extraNegCsv)))

        let rule = SearchRule(
            name: finalName,
            enabled: true,
            url: url,
            minPrice: Double(minPrice),
            maxPrice: Double(maxPrice),
            conditionMode: conditionMode,
            ignoreWanted: true,
            ignoreCommercial: ignoreCommercial,
            requiredKeywords: splitCsv(requiredCsv),
            negativeKeywords: combinedNeg,
            titleNegativeKeywords: nil,
            maxDistanceKm: nil
        )
        cfg.searches.append(rule)
        if await client.saveDealConfig(cfg) {
            client.showToast("✅ \"\(finalName)\" angelegt!")
            if runDeepScan {
                await client.triggerDealScan(deep: true, searchName: finalName)
            }
            onSaved()
            dismiss()
        }
    }
}
