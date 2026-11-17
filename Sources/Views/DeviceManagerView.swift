import SwiftUI

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
                Section("Schnell-Vorlagen") {
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
                            .foregroundStyle(.cyan)
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

struct DeviceManagerSheet: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let onChanged: () -> Void

    @State private var showQuickAdd = false
    @State private var deleteTargetIndex: Int?
    @State private var deleteTargetName: String = ""
    @State private var deleteAlsoAds = false

    var body: some View {
        NavigationStack {
            List {
                if let searches = client.dealConfig?.searches, !searches.isEmpty {
                    ForEach(Array(searches.enumerated()), id: \.offset) { idx, rule in
                        DeviceRuleRow(
                            index: idx,
                            rule: rule,
                            onSavePrice: { minP, maxP in
                                Task {
                                    if await client.updateQuickPrice(index: idx, minPrice: minP, maxPrice: maxP) {
                                        onChanged()
                                    }
                                }
                            },
                            onToggleEnabled: { newVal in
                                Task {
                                    guard var cfg = client.dealConfig, idx < cfg.searches.count else { return }
                                    cfg.searches[idx].enabled = newVal
                                    if await client.saveDealConfig(cfg) {
                                        client.showToast(newVal ? "▶ Aktiviert" : "⏸ Pausiert")
                                        onChanged()
                                    }
                                }
                            },
                            onDeepScan: {
                                Task {
                                    await client.triggerDealScan(deep: true, searchName: rule.name)
                                    dismiss()
                                }
                            },
                            onOpenURL: {
                                if let u = URL(string: rule.url) { openURL(u) }
                            },
                            onDelete: {
                                deleteTargetIndex = idx
                                deleteTargetName = rule.name
                                deleteAlsoAds = false
                            }
                        )
                    }
                } else {
                    ContentUnavailableView("Keine Geräte", systemImage: "magnifyingglass", description: Text("Tippe oben rechts auf +, um ein Gerät hinzuzufügen."))
                }
            }
            .navigationTitle("Geräte & Preise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Fertig") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showQuickAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .task {
                await client.fetchDealConfig()
            }
            .sheet(isPresented: $showQuickAdd) {
                QuickAddDeviceSheet(onSaved: {
                    Task {
                        await client.fetchDealConfig()
                        onChanged()
                    }
                })
            }
            .confirmationDialog(
                "\"\(deleteTargetName)\" löschen?",
                isPresented: Binding(
                    get: { deleteTargetIndex != nil },
                    set: { if !$0 { deleteTargetIndex = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Nur Überwachung löschen", role: .destructive) {
                    if let idx = deleteTargetIndex {
                        Task {
                            _ = await client.deleteSearchRule(index: idx, deleteAds: false)
                            onChanged()
                        }
                    }
                }
                Button("Gerät + alle Deals löschen", role: .destructive) {
                    if let idx = deleteTargetIndex {
                        Task {
                            _ = await client.deleteSearchRule(index: idx, deleteAds: true)
                            onChanged()
                        }
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Das Gerät wird aus deiner Pi-Konfiguration entfernt und nicht mehr gescannt.")
            }
        }
    }
}

private struct DeviceRuleRow: View {
    let index: Int
    let rule: SearchRule
    let onSavePrice: (Double, Double) -> Void
    let onToggleEnabled: (Bool) -> Void
    let onDeepScan: () -> Void
    let onOpenURL: () -> Void
    let onDelete: () -> Void

    @State private var minStr: String = ""
    @State private var maxStr: String = ""
    @State private var isOn: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.name).font(.headline)
                    Text(rule.conditionMode == "defective_only" ? "🔧 Defekt / Bastler" : (rule.conditionMode == "any" ? "🎯 Alle Zustände" : "✅ Funktionierend"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .onChange(of: isOn) { _, newVal in
                        if newVal != rule.isEnabled { onToggleEnabled(newVal) }
                    }
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Min €").font(.caption2).foregroundStyle(.secondary)
                    TextField("0", text: $minStr)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }
                Text("–").foregroundStyle(.secondary).padding(.top, 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Max €").font(.caption2).foregroundStyle(.secondary)
                    TextField("500", text: $maxStr)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                }
                Button("Speichern") {
                    let minP = Double(minStr) ?? (rule.minPrice ?? 0)
                    let maxP = Double(maxStr) ?? (rule.maxPrice ?? 500)
                    onSavePrice(minP, maxP)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .font(.caption.bold())
                .padding(.top, 14)
            }

            HStack(spacing: 8) {
                Button { onDeepScan() } label: {
                    Label("Alle Seiten", systemImage: "magnifyingglass")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.indigo)

                Button { onOpenURL() } label: {
                    Label("Öffnen", systemImage: "safari")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(role: .destructive) { onDelete() } label: {
                    Label("Löschen", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .padding(.vertical, 6)
        .onAppear {
            minStr = String(Int((rule.minPrice ?? 0).rounded()))
            maxStr = String(Int((rule.maxPrice ?? 500).rounded()))
            isOn = rule.isEnabled
        }
    }
}
