import SwiftUI

struct DeviceManagerTabView: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.openURL) private var openURL

    @State private var showQuickAdd = false
    @State private var editingIndex: Int?
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
                            Text("Überwachte Geräte & Filter")
                                .font(.system(size: 15, weight: .heavy))
                            Text("Bearbeite Preise, Umkreis (Range), Pflicht- & Ausschluss-Wörter jederzeit im Nachhinein.")
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
                        ForEach(Array(searches.enumerated()), id: \.element.id) { idx, rule in
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
                                onEditFull: {
                                    Haptics.light()
                                    editingIndex = idx
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
            .navigationTitle("Geräte & Filter")
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
            .sheet(
                isPresented: Binding(
                    get: { editingIndex != nil },
                    set: { if !$0 { editingIndex = nil } }
                )
            ) {
                if let idx = editingIndex,
                   let searches = client.dealConfig?.searches,
                   idx < searches.count {
                    EditDeviceRuleSheet(
                        index: idx,
                        initialRule: searches[idx],
                        onSaved: {
                            Task {
                                await client.fetchDealConfig()
                                await client.refreshDealState()
                            }
                        }
                    )
                }
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

// MARK: - Helper to parse Kleinanzeigen URL metadata

enum KleinanzeigenURLHelper {
    static func extractRadiusKm(from url: String) -> Int {
        if let range = url.range(of: #"l\d+r(\d+)"#, options: .regularExpression) {
            let sub = String(url[range])
            if let rIdx = sub.lastIndex(of: "r"),
               let val = Int(sub[sub.index(after: rIdx)...]) {
                return val
            }
        }
        return 0
    }

    static func extractCategory(from url: String) -> String {
        if url.contains("c278") || url.contains("/s-notebooks/") { return "notebooks" }
        if url.contains("c279") || url.contains("/konsolen/") { return "consoles" }
        if url.contains("c173") || url.contains("/s-handy-telekom/") { return "phones" }
        if url.contains("c285") || url.contains("/tablets") { return "tablets" }
        if url.contains("c228") || url.contains("/s-pcs/") { return "pcs" }
        if url.contains("c225") { return "hardware" }
        if url.contains("c245") { return "cameras" }
        if url.contains("c161") || url.contains("/s-multimedia-elektronik/") { return "electronics" }
        return "all"
    }

    static func extractQuery(from url: String, fallbackName: String) -> String {
        guard let kRange = url.range(of: #"/k0[a-z0-9]*"#, options: .regularExpression) else {
            return fallbackName
        }
        let prefix = String(url[..<kRange.lowerBound])
        if let lastSlash = prefix.lastIndex(of: "/") {
            let slug = String(prefix[prefix.index(after: lastSlash)...])
            if !slug.hasPrefix("preis:") && !slug.hasPrefix("s-") && !slug.isEmpty {
                return slug.replacingOccurrences(of: "-", with: " ")
            }
        }
        return fallbackName
    }
}

// MARK: - Device Rule Card

private struct DeviceRuleCard: View {
    let index: Int
    let rule: SearchRule
    let onSavePrice: (Double, Double) -> Void
    let onToggleEnabled: (Bool) -> Void
    let onEditFull: () -> Void
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
        if low.contains("macbook") || low.contains("imac") || low.contains("thinkpad") || low.contains("laptop") { return "laptopcomputer" }
        if low.contains("switch") || low.contains("steam") || low.contains("ps5") || low.contains("playstation") { return "gamecontroller.fill" }
        if low.contains("rtx") || low.contains("gpu") || low.contains("rx ") { return "cpu.fill" }
        return "tag.fill"
    }

    private var badgeColors: [Color] {
        if !isOn { return [.gray, .gray.opacity(0.6)] }
        if rule.conditionMode == "defective_only" { return [HubTheme.amber, HubTheme.rose] }
        return [HubTheme.sky, HubTheme.indigo]
    }

    private var parsedRadiusLabel: String {
        if let maxDist = rule.maxDistanceKm, maxDist > 0 {
            return "📍 \(Int(maxDist)) km"
        }
        let r = KleinanzeigenURLHelper.extractRadiusKm(from: rule.url)
        return r > 0 ? "📍 \(r) km" : "🌍 DE-weit"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                Button(action: onEditFull) {
                    HStack(spacing: 10) {
                        IconBadge(symbol: deviceSymbol, colors: badgeColors, size: 38, iconSize: 17)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name)
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(isOn ? .white : .secondary)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text(rule.conditionMode == "defective_only" ? "🔧 Defekt / Bastler" : (rule.conditionMode == "any" ? "🎯 Alle" : "✅ Funktionierend"))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(rule.conditionMode == "defective_only" ? HubTheme.amber : HubTheme.emerald)
                                Text("• \(parsedRadiusLabel)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(HubTheme.sky)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)

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

            // Keywords & Filter Summary Pills (Tap to open Full Editor)
            Button(action: onEditFull) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        let reqs = rule.requiredKeywords ?? []
                        let negs = rule.negativeKeywords ?? []

                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                            Text(reqs.isEmpty ? "Pflichtwörter: Alle" : "Pflicht: \(reqs.prefix(3).joined(separator: ", "))\(reqs.count > 3 ? " +\(reqs.count - 3)" : "")")
                        }
                        .font(.system(size: 10.5, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(HubTheme.emerald.opacity(0.16), in: Capsule())
                        .foregroundStyle(HubTheme.emerald)

                        HStack(spacing: 4) {
                            Image(systemName: "nosign")
                            Text("\(negs.count) Ausschluss-Wörter")
                        }
                        .font(.system(size: 10.5, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(HubTheme.rose.opacity(0.15), in: Capsule())
                        .foregroundStyle(HubTheme.rose)

                        if rule.ignoreCommercial == true {
                            Text("Privat-Only")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(HubTheme.purple.opacity(0.18), in: Capsule())
                                .foregroundStyle(HubTheme.purple)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

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
                        Text("Preis OK")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .frame(width: 70, height: 48)
                    .background(LinearGradient(colors: [HubTheme.sky, HubTheme.indigo], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            // Bottom Action Bar
            HStack(spacing: 7) {
                Button {
                    onEditFull()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Bearbeiten")
                    }
                    .font(.system(size: 11.5, weight: .heavy))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(HubTheme.sky.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(HubTheme.sky.opacity(0.55), lineWidth: 1))
                    .foregroundStyle(HubTheme.sky)
                }
                .buttonStyle(.plain)

                Button {
                    onDeepScan()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkle.magnifyingglass")
                        Text("Tiefenscan")
                    }
                    .font(.system(size: 11.5, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(HubTheme.indigo.opacity(0.22), in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(HubTheme.indigo.opacity(0.5), lineWidth: 1))
                    .foregroundStyle(Color(red: 0.78, green: 0.82, blue: 1.0))
                }
                .buttonStyle(.plain)

                Button {
                    onOpenURL()
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 12, weight: .bold))
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

// MARK: - Full Edit Sheet for Any Existing Monitored Device

struct EditDeviceRuleSheet: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let index: Int
    let initialRule: SearchRule
    let onSaved: () -> Void

    @State private var name: String = ""
    @State private var query: String = ""
    @State private var url: String = ""
    @State private var minPrice: Int = 0
    @State private var maxPrice: Int = 500
    @State private var radiusKm: Int = 75
    @State private var maxDistanceLimitKm: Int = 0
    @State private var category: String = "all"
    @State private var conditionMode: String = "working_only"
    @State private var ignoreCommercial: Bool = false
    @State private var ignoreWanted: Bool = true

    @State private var requiredWords: [String] = []
    @State private var newRequiredInput: String = ""

    @State private var negativeWords: [String] = []
    @State private var newNegativeInput: String = ""
    @State private var negFilterText: String = ""
    @State private var showRawNegEditor: Bool = false
    @State private var rawNegCsv: String = ""

    @State private var titleNegativeCsv: String = ""
    @State private var runDeepScanAfterSave: Bool = false
    @State private var isSaving: Bool = false
    @State private var didAppear: Bool = false

    private let radii = [
        (20, "20 km (Frankfurt)"),
        (30, "30 km"),
        (50, "50 km"),
        (75, "75 km (Rhein-Main)"),
        (100, "100 km"),
        (150, "150 km"),
        (200, "200 km"),
        (0, "Deutschlandweit (DE)")
    ]

    private let categories = [
        ("all", "Alle Kategorien"),
        ("electronics", "Elektronik"),
        ("notebooks", "Notebooks / MacBooks"),
        ("consoles", "Konsolen"),
        ("phones", "Handy & Telefon"),
        ("tablets", "Tablets & iPads"),
        ("pcs", "PCs"),
        ("hardware", "PC-Hardware / GPUs"),
        ("cameras", "Foto & Kameras")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("1. Gerätename & Suchbegriff") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Anzeigename")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        TextField("Name (z. B. PlayStation 5 Konsole)", text: $name)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kleinanzeigen-Suchbegriff (aktualisiert URL)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("Suchbegriff (z. B. ps5)", text: $query)
                                .autocorrectionDisabled()
                            Button("URL neu bauen") {
                                Haptics.light()
                                rebuildURLFromFields()
                            }
                            .font(.caption.bold())
                            .buttonStyle(.borderedProminent)
                            .tint(HubTheme.sky)
                        }
                    }
                }

                Section("2. Umkreis (Range), Kategorie & Preisspanne") {
                    Picker("Such-Umkreis (Kleinanzeigen)", selection: $radiusKm) {
                        ForEach(radii, id: \.0) { r, lbl in Text(lbl).tag(r) }
                    }
                    .onChange(of: radiusKm) { _, newR in
                        guard didAppear else { return }
                        updateRadiusInNameAndURL(newRadius: newR)
                    }

                    Stepper(value: $maxDistanceLimitKm, in: 0...500, step: 10) {
                        HStack {
                            Text("Strikter Distanz-Filter")
                            Spacer()
                            Text(maxDistanceLimitKm == 0 ? "Wie Umkreis" : "max. \(maxDistanceLimitKm) km")
                                .font(.caption.bold())
                                .foregroundStyle(HubTheme.sky)
                        }
                    }

                    Picker("Kategorie", selection: $category) {
                        ForEach(categories, id: \.0) { c, lbl in Text(lbl).tag(c) }
                    }
                    .onChange(of: category) { _, _ in
                        guard didAppear else { return }
                        rebuildURLFromFields()
                    }

                    HStack {
                        Text("Min Preis (€)")
                        Spacer()
                        TextField("Min", value: $minPrice, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    .onChange(of: minPrice) { _, _ in
                        guard didAppear else { return }
                        rebuildURLFromFields()
                    }

                    HStack {
                        Text("Max Preis (€)")
                        Spacer()
                        TextField("Max", value: $maxPrice, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    .onChange(of: maxPrice) { _, _ in
                        guard didAppear else { return }
                        rebuildURLFromFields()
                    }
                }

                Section("3. Zustands-Modus & Anbieter") {
                    Picker("Zustand", selection: $conditionMode) {
                        Text("✅ Funktionierend").tag("working_only")
                        Text("🔧 Defekt / Bastler").tag("defective_only")
                        Text("🎯 Alle").tag("any")
                    }
                    .pickerStyle(.segmented)

                    Toggle("Gewerbliche Anbieter (PRO) ignorieren", isOn: $ignoreCommercial)
                    Toggle("Gesuche ('Suche...') ignorieren", isOn: $ignoreWanted)
                }

                Section {
                    HStack {
                        TextField("Neues Pflicht-Wort (oder kommagetrennt)", text: $newRequiredInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button {
                            addRequiredWords()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(HubTheme.emerald)
                        }
                        .disabled(newRequiredInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if requiredWords.isEmpty {
                        Text("Keine Pflicht-Keywords aktiv (jedes Inserat aus der Suche wird geprüft).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        FlowChipGrid(words: requiredWords, color: HubTheme.emerald) { wordToRemove in
                            Haptics.light()
                            requiredWords.removeAll { $0.lowercased() == wordToRemove.lowercased() }
                        }
                        Button(role: .destructive) {
                            Haptics.warning()
                            requiredWords.removeAll()
                        } label: {
                            Text("Alle Pflicht-Keywords leeren")
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("4. Pflicht-Keywords (\(requiredWords.count)) – Mindestens 1 muss vorkommen")
                }

                Section {
                    HStack {
                        TextField("Wort ausschließen (z. B. hülle, karton)", text: $newNegativeInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Button {
                            addNegativeWords()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(HubTheme.rose)
                        }
                        .disabled(newNegativeInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    }

                    if !negativeWords.isEmpty {
                        TextField("🔍 In \(negativeWords.count) Ausschluss-Wörtern filtern…", text: $negFilterText)
                            .font(.caption)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)

                        let filtered = negFilterText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? negativeWords
                            : negativeWords.filter { $0.localizedCaseInsensitiveContains(negFilterText) }

                        FlowChipGrid(words: filtered, color: HubTheme.rose) { wordToRemove in
                            Haptics.light()
                            negativeWords.removeAll { $0.lowercased() == wordToRemove.lowercased() }
                            rawNegCsv = negativeWords.joined(separator: ", ")
                        }
                    }

                    DisclosureGroup("Als kommagetrennten Text bearbeiten", isExpanded: $showRawNegEditor) {
                        TextEditor(text: $rawNegCsv)
                            .frame(minHeight: 80)
                            .font(.caption.monospaced())
                            .onChange(of: rawNegCsv) { _, newVal in
                                negativeWords = splitCsv(newVal)
                            }
                    }
                    .font(.caption)
                } header: {
                    Text("5. Ausschluss-Keywords (\(negativeWords.count)) – Tippen auf × zum Löschen")
                }

                Section("6. Titel-Ausschluss & Direkt-URL") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nur im Titel verbotene Wörter (kommagetrennt, optional)")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        TextField("z. B. hülle, tasche, defekt", text: $titleNegativeCsv)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kleinanzeigen Such-URL")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        TextField("https://www.kleinanzeigen.de/...", text: $url)
                            .font(.caption2.monospaced())
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    if let testURL = URL(string: url), !url.isEmpty {
                        Button {
                            openURL(testURL)
                        } label: {
                            Label("Such-URL in Safari testen", systemImage: "safari")
                                .font(.caption.bold())
                        }
                    }
                }

                Section {
                    Toggle("🔎 Nach dem Speichern direkt Tiefenscan starten", isOn: $runDeepScanAfterSave)
                }
            }
            .navigationTitle("Gerät bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Speichern") {
                        Task { await saveChanges() }
                    }
                    .bold()
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || url.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                guard !didAppear else { return }
                name = initialRule.name
                url = initialRule.url
                minPrice = Int((initialRule.minPrice ?? 0).rounded())
                maxPrice = Int((initialRule.maxPrice ?? 500).rounded())
                radiusKm = KleinanzeigenURLHelper.extractRadiusKm(from: initialRule.url)
                maxDistanceLimitKm = Int((initialRule.maxDistanceKm ?? 0).rounded())
                category = KleinanzeigenURLHelper.extractCategory(from: initialRule.url)
                query = KleinanzeigenURLHelper.extractQuery(from: initialRule.url, fallbackName: initialRule.name)
                conditionMode = initialRule.conditionMode ?? "working_only"
                ignoreCommercial = initialRule.ignoreCommercial ?? false
                ignoreWanted = initialRule.ignoreWanted ?? true
                requiredWords = initialRule.requiredKeywords ?? []
                negativeWords = initialRule.negativeKeywords ?? []
                rawNegCsv = negativeWords.joined(separator: ", ")
                titleNegativeCsv = (initialRule.titleNegativeKeywords ?? []).joined(separator: ", ")
                didAppear = true
            }
        }
    }

    private func splitCsv(_ s: String) -> [String] {
        var seen = Set<String>()
        var res: [String] = []
        for part in s.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let low = trimmed.lowercased()
            if !seen.contains(low) {
                seen.insert(low)
                res.append(trimmed)
            }
        }
        return res
    }

    private func addRequiredWords() {
        Haptics.light()
        let added = splitCsv(newRequiredInput)
        for w in added {
            if !requiredWords.contains(where: { $0.lowercased() == w.lowercased() }) {
                requiredWords.append(w)
            }
        }
        newRequiredInput = ""
    }

    private func addNegativeWords() {
        Haptics.light()
        let added = splitCsv(newNegativeInput)
        for w in added {
            if !negativeWords.contains(where: { $0.lowercased() == w.lowercased() }) {
                negativeWords.insert(w, at: 0)
            }
        }
        rawNegCsv = negativeWords.joined(separator: ", ")
        newNegativeInput = ""
    }

    private func updateRadiusInNameAndURL(newRadius: Int) {
        // Also update "(75 km)" or "(DE)" in name if present
        let newSuffix = newRadius > 0 ? "(\(newRadius) km)" : "(DE)"
        if let r = name.range(of: #"\((\d+\s*km|DE)\)"#, options: .regularExpression) {
            name.replaceSubrange(r, with: newSuffix)
        }
        rebuildURLFromFields()
    }

    private func rebuildURLFromFields() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        Task {
            if let built = await client.buildKleinanzeigenURL(
                query: q,
                minPrice: minPrice,
                maxPrice: maxPrice,
                radiusKm: radiusKm,
                category: category
            ) {
                url = built
            }
        }
    }

    private func saveChanges() async {
        // Include any unsubmitted text still typed in the add boxes
        if !newRequiredInput.trimmingCharacters(in: .whitespaces).isEmpty {
            addRequiredWords()
        }
        if !newNegativeInput.trimmingCharacters(in: .whitespaces).isEmpty {
            addNegativeWords()
        }

        isSaving = true
        defer { isSaving = false }

        if client.dealConfig == nil {
            await client.fetchDealConfig()
        }
        guard var cfg = client.dealConfig, index < cfg.searches.count else {
            client.showToast("Konfiguration konnte nicht geladen werden")
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedURL = url.trimmingCharacters(in: .whitespaces)
        let titleNegList = splitCsv(titleNegativeCsv)

        let updatedRule = SearchRule(
            name: trimmedName,
            enabled: cfg.searches[index].enabled ?? true,
            url: trimmedURL,
            minPrice: Double(minPrice),
            maxPrice: Double(maxPrice),
            conditionMode: conditionMode,
            ignoreWanted: ignoreWanted,
            ignoreCommercial: ignoreCommercial,
            requiredKeywords: requiredWords,
            negativeKeywords: negativeWords,
            titleNegativeKeywords: titleNegList.isEmpty ? nil : titleNegList,
            maxDistanceKm: maxDistanceLimitKm > 0 ? Double(maxDistanceLimitKm) : nil
        )

        cfg.searches[index] = updatedRule
        if await client.saveDealConfig(cfg) {
            client.showToast("✅ \"\(trimmedName)\" gespeichert!")
            if runDeepScanAfterSave {
                await client.triggerDealScan(deep: true, searchName: trimmedName)
            }
            onSaved()
            dismiss()
        }
    }
}

// MARK: - Interactive Chip Grid for Keywords

private struct FlowChipGrid: View {
    let words: [String]
    let color: Color
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(words, id: \.self) { word in
                Button {
                    onRemove(word)
                } label: {
                    HStack(spacing: 4) {
                        Text(word)
                            .font(.system(size: 11.5, weight: .bold))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(color.opacity(0.16), in: Capsule())
                    .overlay(Capsule().stroke(color.opacity(0.45), lineWidth: 1))
                    .foregroundStyle(color)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Quick Add New Device Sheet

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
