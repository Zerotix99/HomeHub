import SwiftUI

enum DealViewFilter: String, CaseIterable, Identifiable {
    case deals, favorites, price_drops, contacted, archived, ignored
    var id: String { rawValue }
    var title: String {
        switch self {
        case .deals: return "🔥 Deals"
        case .favorites: return "⭐ Favoriten"
        case .price_drops: return "📉 Drops"
        case .contacted: return "💬 Kontakt"
        case .archived: return "📦 Archiv"
        case .ignored: return "🚫 Ignoriert"
        }
    }
}

enum DealSortOption: String, CaseIterable, Identifiable {
    case newest, score, price_asc, distance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: return "Neueste"
        case .score: return "Bester Score"
        case .price_asc: return "Günstigste"
        case .distance: return "Nächste"
        }
    }
}

struct DealRadarView: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.openURL) private var openURL

    @State private var selectedView: DealViewFilter = .deals
    @State private var selectedCategory: String = "all"
    @State private var sortOption: DealSortOption = .newest
    @State private var searchText: String = ""

    @State private var showAddDevice = false
    @State private var showManageDevices = false
    @State private var selectedDeal: DealItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Live scan progress banner
                if let rt = client.dealState?.runtime, rt.isScanning {
                    HStack(spacing: 10) {
                        ProgressView().tint(.cyan)
                        Text(rt.scanProgress?.isEmpty == false ? rt.scanProgress! : "Scannt Kleinanzeigen…")
                            .font(.caption.weight(.semibold))
                            .lineLimit(2)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.cyan.opacity(0.18))
                }

                // Filter view pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(DealViewFilter.allCases) { f in
                            let isSel = selectedView == f
                            Button {
                                Haptics.light()
                                selectedView = f
                                Task { await reloadDeals() }
                            } label: {
                                Text("\(f.title) \(countBadge(for: f))")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(isSel ? Color.cyan.opacity(0.22) : Color.white.opacity(0.06), in: Capsule())
                                    .overlay(Capsule().stroke(isSel ? Color.cyan : Color.white.opacity(0.08), lineWidth: 1))
                                    .foregroundStyle(isSel ? .cyan : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                // Category & Sort bar
                HStack(spacing: 10) {
                    Menu {
                        Button("Alle Geräte") {
                            selectedCategory = "all"
                            Task { await reloadDeals() }
                        }
                        ForEach(client.dealState?.stats.byCategory ?? []) { cat in
                            Button("\(cat.name) (\(cat.deals))") {
                                selectedCategory = cat.name
                                Task { await reloadDeals() }
                            }
                        }
                    } label: {
                        Label(selectedCategory == "all" ? "Alle Geräte" : selectedCategory, systemImage: "line.3.horizontal.decrease.circle")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.07), in: Capsule())
                    }

                    Spacer()

                    Menu {
                        ForEach(DealSortOption.allCases) { opt in
                            Button {
                                sortOption = opt
                                Task { await reloadDeals() }
                            } label: {
                                if sortOption == opt {
                                    Label(opt.title, systemImage: "checkmark")
                                } else {
                                    Text(opt.title)
                                }
                            }
                        }
                    } label: {
                        Label(sortOption.title, systemImage: "arrow.up.arrow.down")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.07), in: Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                // Deals List
                if client.deals.isEmpty {
                    ContentUnavailableView(
                        "Keine Einträge",
                        systemImage: "tag.slash",
                        description: Text("Passe die Filter an oder starte einen Tiefenscan über alle Seiten.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(client.deals) { deal in
                                DealCardRow(deal: deal, onOpenDetail: {
                                    selectedDeal = deal
                                }, onStateChange: { newState in
                                    Task {
                                        await client.updateDealState(adId: deal.adId, userState: newState)
                                        await reloadDeals()
                                    }
                                }, onOpenLink: {
                                    if let url = URL(string: deal.url) { openURL(url) }
                                })
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .refreshable {
                        await client.refreshDealState()
                        await reloadDeals()
                    }
                }
            }
            .background(Color(red: 0.03, green: 0.05, blue: 0.10).ignoresSafeArea())
            .navigationTitle("Deal Radar")
            .searchable(text: $searchText, prompt: "Titel, Ort, Beschreibung…")
            .onChange(of: searchText) { _, _ in
                Task { await reloadDeals() }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showAddDevice = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Button {
                        showManageDevices = true
                    } label: {
                        Image(systemName: "slider.horizontal.below.rectangle")
                    }
                    Menu {
                        Button {
                            Task { await client.triggerDealScan(deep: false) }
                        } label: {
                            Label("Schnellscan (Seite 1)", systemImage: "arrow.clockwise")
                        }
                        Button {
                            Task { await client.triggerDealScan(deep: true) }
                        } label: {
                            Label("Tiefenscan (Alle Seiten)", systemImage: "magnifyingglass.circle")
                        }
                        Divider()
                        Button {
                            Task { await client.sendTestPush() }
                        } label: {
                            Label("Test-Push an ntfy", systemImage: "bell.badge")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showAddDevice) {
                QuickAddDeviceSheet(onSaved: {
                    Task {
                        await client.fetchDealConfig()
                        await client.refreshDealState()
                        await reloadDeals()
                    }
                })
            }
            .sheet(isPresented: $showManageDevices) {
                DeviceManagerSheet(onChanged: {
                    Task {
                        await client.refreshDealState()
                        await reloadDeals()
                    }
                })
            }
            .sheet(item: $selectedDeal) { deal in
                DealDetailSheet(deal: deal, onUpdated: {
                    Task { await reloadDeals() }
                })
            }
        }
        .task {
            await client.refreshDealState()
            await reloadDeals()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                let wasScanning = client.dealState?.runtime.isScanning ?? false
                await client.refreshDealState()
                let isScanning = client.dealState?.runtime.isScanning ?? false
                if wasScanning && !isScanning {
                    await reloadDeals()
                }
            }
        }
    }

    private func reloadDeals() async {
        await client.fetchDeals(
            view: selectedView.rawValue,
            category: selectedCategory,
            query: searchText,
            sort: sortOption.rawValue
        )
    }

    private func countBadge(for filter: DealViewFilter) -> String {
        guard let st = client.dealState?.stats else { return "" }
        switch filter {
        case .deals: return "(\(st.activeDeals))"
        case .favorites: return st.favorites > 0 ? "(\(st.favorites))" : ""
        case .price_drops: return st.priceDrops > 0 ? "(\(st.priceDrops))" : ""
        case .contacted: return st.contacted > 0 ? "(\(st.contacted))" : ""
        case .archived: return st.archived > 0 ? "(\(st.archived))" : ""
        case .ignored: return "(\(st.ignored))"
        }
    }
}

struct DealCardRow: View {
    let deal: DealItem
    let onOpenDetail: () -> Void
    let onStateChange: (String) -> Void
    let onOpenLink: () -> Void

    private var scoreColor: Color {
        let s = deal.dealScore ?? 0
        if s >= 80 { return .green }
        if s >= 60 { return .cyan }
        return .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Image header with score & price drop overlays
            ZStack(alignment: .topLeading) {
                if let imgStr = deal.imageUrl, let url = URL(string: imgStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Color.black.opacity(0.4).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                        }
                    }
                    .frame(height: 175)
                    .clipped()
                } else {
                    Color.black.opacity(0.35)
                        .frame(height: 120)
                        .overlay(Image(systemName: "tag").font(.title).foregroundStyle(.secondary))
                }

                HStack {
                    if !deal.isIgnored {
                        Text("Score \(deal.dealScore ?? 50)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(scoreColor.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                    } else {
                        Text("Ignoriert")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Spacer()
                    if let drop = deal.priceDropEur, drop > 0 {
                        Text("📉 -\(Int(drop.rounded())) €")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.pink.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(.white)
                    }
                }
                .padding(10)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(deal.price)
                        .font(.title3.bold())
                        .foregroundStyle(.green)
                    if let drop = deal.priceDropEur, drop > 0, let initP = deal.initialPriceNum {
                        Text("\(Int(initP.rounded())) €")
                            .font(.caption)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(deal.searchName)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.cyan.opacity(0.16), in: Capsule())
                        .foregroundStyle(.cyan)
                        .lineLimit(1)
                }

                Text(deal.title)
                    .font(.headline)
                    .lineLimit(2)
                    .onTapGesture { onOpenDetail() }

                HStack(spacing: 8) {
                    Label("\(deal.location ?? "Umland FFM")\(deal.distance.map { " (\($0))" } ?? "")", systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Badges (Shipping, Seller, Commercial)
                HStack(spacing: 6) {
                    if let ship = deal.shipping, !ship.isEmpty {
                        miniTag("📦 \(ship)", tint: ship.lowercased().contains("versand") ? .green : .gray)
                    }
                    if let rating = deal.sellerInfo?.rating, !rating.isEmpty {
                        miniTag("👤 \(rating)", tint: rating.contains("TOP") ? .green : .orange)
                    }
                    if deal.isCommercial == true {
                        miniTag("PRO", tint: .indigo)
                    }
                }

                if deal.isIgnored {
                    Text(deal.status.replacingOccurrences(of: "ignored: ", with: "🚫 "))
                        .font(.caption2)
                        .foregroundStyle(.pink)
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.pink.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }

                if let warns = deal.warnings, !warns.isEmpty {
                    Text(warns.joined(separator: " • "))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }

                Divider().padding(.vertical, 2)

                HStack {
                    Button {
                        onStateChange(deal.effectiveState == "favorite" ? "new" : "favorite")
                    } label: {
                        Image(systemName: deal.effectiveState == "favorite" ? "star.fill" : "star")
                            .foregroundStyle(deal.effectiveState == "favorite" ? .yellow : .secondary)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onStateChange(deal.effectiveState == "contacted" ? "new" : "contacted")
                    } label: {
                        Image(systemName: deal.effectiveState == "contacted" ? "message.fill" : "message")
                            .foregroundStyle(deal.effectiveState == "contacted" ? .cyan : .secondary)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onStateChange(deal.effectiveState == "archived" ? "new" : "archived")
                    } label: {
                        Image(systemName: "archivebox")
                            .foregroundStyle(deal.effectiveState == "archived" ? .orange : .secondary)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Details") { onOpenDetail() }
                        .buttonStyle(.bordered)
                        .font(.caption.weight(.semibold))

                    Button("Öffnen ↗") { onOpenLink() }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .font(.caption.weight(.semibold))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(deal.effectiveState == "favorite" ? Color.yellow.opacity(0.45) : Color.white.opacity(0.09), lineWidth: 1)
        )
    }

    private func miniTag(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.16), in: Capsule())
            .foregroundStyle(tint == .gray ? .secondary : tint)
            .lineLimit(1)
    }
}

struct DealDetailSheet: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let deal: DealItem
    let onUpdated: () -> Void

    @State private var noteText: String = ""
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("Übersicht") {
                    LabeledContent("Preis", value: deal.price)
                    LabeledContent("Suchauftrag", value: deal.searchName)
                    LabeledContent("Deal-Score", value: "\(deal.dealScore ?? 0) / 100")
                    if let loc = deal.location {
                        LabeledContent("Ort", value: "\(loc)\(deal.distance.map { " (\($0))" } ?? "")")
                    }
                    if let ship = deal.shipping, !ship.isEmpty {
                        LabeledContent("Versand", value: ship)
                    }
                    if let s = deal.sellerInfo {
                        if let r = s.rating { LabeledContent("Verkäufer", value: r) }
                        if let since = s.activeSince { LabeledContent("Aktiv seit", value: since) }
                    }
                }

                if let attrs = deal.attributes, !attrs.isEmpty {
                    Section("Attribute") {
                        ForEach(attrs.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                            LabeledContent(k, value: v)
                        }
                    }
                }

                if let desc = deal.description, !desc.isEmpty {
                    Section("Beschreibung") {
                        Text(desc).font(.footnote)
                    }
                }

                Section("Persönliche Notiz") {
                    TextField("Notiz eingeben…", text: $noteText, axis: .vertical)
                        .lineLimit(2...5)
                    Button("Notiz speichern") {
                        Task {
                            await client.updateDealState(adId: deal.adId, notes: noteText)
                            client.showToast("💾 Notiz gespeichert")
                            onUpdated()
                        }
                    }
                }

                Section {
                    Button {
                        if let url = URL(string: deal.url) { openURL(url) }
                    } label: {
                        Label("Auf Kleinanzeigen öffnen", systemImage: "safari")
                    }
                    Button("Aus Datenbank löschen", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("Deal-Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { dismiss() }
                }
            }
            .onAppear { noteText = deal.notes ?? "" }
            .confirmationDialog("Inserat aus DB entfernen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    Task {
                        await client.deleteDeal(adId: deal.adId)
                        onUpdated()
                        dismiss()
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            }
        }
    }
}
