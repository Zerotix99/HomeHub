import SwiftUI

enum DealViewFilter: String, CaseIterable, Identifiable {
    case deals, favorites, price_drops, contacted, archived, ignored
    var id: String { rawValue }
    var label: String {
        switch self {
        case .deals: return "Deals"
        case .favorites: return "Favoriten"
        case .price_drops: return "Drops"
        case .contacted: return "Kontaktiert"
        case .archived: return "Archiv"
        case .ignored: return "Ignoriert"
        }
    }
    var symbol: String {
        switch self {
        case .deals: return "flame.fill"
        case .favorites: return "star.fill"
        case .price_drops: return "arrow.down.right.circle.fill"
        case .contacted: return "bubble.left.and.bubble.right.fill"
        case .archived: return "archivebox.fill"
        case .ignored: return "nosign"
        }
    }
    var color: Color {
        switch self {
        case .deals: return HubTheme.emerald
        case .favorites: return HubTheme.amber
        case .price_drops: return HubTheme.rose
        case .contacted: return HubTheme.sky
        case .archived: return .gray
        case .ignored: return HubTheme.rose
        }
    }
}

enum DealSortOption: String, CaseIterable, Identifiable {
    case newest, score, price_asc, distance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: return "Neueste zuerst"
        case .score: return "Bester Deal-Score"
        case .price_asc: return "Günstigste zuerst"
        case .distance: return "Nächste zuerst"
        }
    }
}

struct DealRadarView: View {
    @EnvironmentObject var client: HubClient
    @Environment(\.openURL) private var openURL
    var switchToDevicesTab: () -> Void = {}

    @State private var selectedView: DealViewFilter = .deals
    @State private var selectedCategory: String = "all"
    @State private var sortOption: DealSortOption = .newest
    @State private var searchText: String = ""

    @State private var showAddDevice = false
    @State private var selectedDeal: DealItem?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // KPI Dashboard Strip (just like Web Dashboard!)
                    kpiHeaderGrid

                    // Quick Action Bar
                    quickActionButtons

                    // Live Scan Progress Banner
                    if let rt = client.dealState?.runtime, rt.isScanning {
                        HStack(spacing: 10) {
                            ProgressView().tint(HubTheme.sky)
                            Text(rt.scanProgress?.isEmpty == false ? rt.scanProgress! : "Scannt Kleinanzeigen…")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Spacer()
                        }
                        .padding(12)
                        .background(
                            LinearGradient(colors: [HubTheme.sky.opacity(0.25), HubTheme.indigo.opacity(0.25)], startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(HubTheme.sky.opacity(0.5), lineWidth: 1))
                    }

                    // Symbolic Filter Tabs
                    filterTabsStrip

                    // Category & Sort Row
                    categoryAndSortBar

                    // Deals Cards
                    if client.deals.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "tag.slash.fill")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)
                            Text("Keine Einträge in dieser Ansicht")
                                .font(.headline)
                            Text("Passe die Filter an oder starte einen Tiefenscan über alle Seiten.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 44)
                        .hubCard(cornerRadius: 18)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(client.deals) { deal in
                                DealCardRow(
                                    deal: deal,
                                    onOpenDetail: { selectedDeal = deal },
                                    onStateChange: { newState in
                                        Task {
                                            await client.updateDealState(adId: deal.adId, userState: newState)
                                            await reloadDeals()
                                        }
                                    },
                                    onDelete: {
                                        Task {
                                            await client.deleteDeal(adId: deal.adId)
                                            await reloadDeals()
                                        }
                                    },
                                    onOpenLink: {
                                        if let url = URL(string: deal.url) { openURL(url) }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 30)
            }
            .background(HubTheme.bg.ignoresSafeArea())
            .navigationTitle("Deal Radar")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Suche nach Titel, Ort, Notiz…")
            .onChange(of: searchText) { _, _ in
                Task { await reloadDeals() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(client.dealState?.runtime.isScanning == true ? HubTheme.sky : HubTheme.emerald)
                            .frame(width: 8, height: 8)
                        Text(client.dealState?.runtime.isScanning == true ? "Scannt…" : "24/7 Aktiv")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await client.sendTestPush() }
                    } label: {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(HubTheme.amber)
                    }
                }
            }
            .refreshable {
                await client.refreshDealState()
                await reloadDeals()
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
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                let wasScanning = client.dealState?.runtime.isScanning ?? false
                await client.refreshDealState()
                let isScanning = client.dealState?.runtime.isScanning ?? false
                if wasScanning && !isScanning {
                    await reloadDeals()
                }
            }
        }
    }

    // MARK: - Subviews

    private var kpiHeaderGrid: some View {
        let st = client.dealState?.stats
        let rt = client.dealState?.runtime
        return HStack(spacing: 8) {
            kpiTile(label: "DEALS", val: "\(st?.activeDeals ?? 0)", sub: "Heute: \(st?.todayDeals ?? 0)", color: HubTheme.emerald)
            kpiTile(label: "DROPS", val: "\(st?.priceDrops ?? 0)", sub: "Favs: \(st?.favorites ?? 0)", color: HubTheme.rose)
            kpiTile(label: "GEPRÜFT", val: "\(st?.totalSeen ?? 0)", sub: String(format: "%.1f%% Quote", st?.matchRatePct ?? 0), color: HubTheme.sky)
            kpiTile(label: "SCAN", val: rt?.isScanning == true ? "Läuft" : fmtSec(rt?.nextScanInSec ?? 0), sub: rt?.lastDurationSec.map { String(format: "%.0fs Dauer", $0) } ?? "5m Takt", color: HubTheme.amber)
        }
    }

    private func kpiTile(label: String, val: String, sub: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9.5, weight: .heavy)).foregroundStyle(.secondary)
            Text(val).font(.system(size: 17, weight: .heavy)).foregroundStyle(color).lineLimit(1)
            Text(sub).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .hubCard(cornerRadius: 14)
    }

    private var quickActionButtons: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.light()
                showAddDevice = true
            } label: {
                Label("Gerät", systemImage: "plus.circle.fill")
                    .font(.system(size: 12.5, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(LinearGradient(colors: [HubTheme.emerald, .teal], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                Task { await client.triggerDealScan(deep: false) }
            } label: {
                Label("Schnellscan", systemImage: "arrow.clockwise")
                    .font(.system(size: 12.5, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(LinearGradient(colors: [HubTheme.sky, HubTheme.indigo], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            Button {
                Task { await client.triggerDealScan(deep: true) }
            } label: {
                Label("Alle Seiten", systemImage: "sparkle.magnifyingglass")
                    .font(.system(size: 12.5, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(HubTheme.indigo.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(HubTheme.indigo.opacity(0.6), lineWidth: 1))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private var filterTabsStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(DealViewFilter.allCases) { f in
                    let isSel = selectedView == f
                    Button {
                        Haptics.light()
                        selectedView = f
                        Task { await reloadDeals() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: f.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(isSel ? f.color : .secondary)
                            Text(f.label)
                                .font(.system(size: 12, weight: .bold))
                            let cnt = countValue(for: f)
                            if cnt > 0 {
                                Text("\(cnt)")
                                    .font(.system(size: 10, weight: .heavy))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.white.opacity(0.14), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(isSel ? f.color.opacity(0.18) : HubTheme.card, in: Capsule())
                        .overlay(Capsule().stroke(isSel ? f.color.opacity(0.6) : HubTheme.border, lineWidth: 1))
                        .foregroundStyle(isSel ? .white : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var categoryAndSortBar: some View {
        HStack(spacing: 8) {
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
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(HubTheme.sky)
                    Text(selectedCategory == "all" ? "Alle Geräte" : selectedCategory)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .hubCard(cornerRadius: 10)
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
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .foregroundStyle(HubTheme.indigo)
                    Text(sortOption.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .hubCard(cornerRadius: 10)
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

    private func countValue(for filter: DealViewFilter) -> Int {
        guard let st = client.dealState?.stats else { return 0 }
        switch filter {
        case .deals: return st.activeDeals
        case .favorites: return st.favorites
        case .price_drops: return st.priceDrops
        case .contacted: return st.contacted
        case .archived: return st.archived
        case .ignored: return st.ignored
        }
    }

    private func fmtSec(_ sec: Int) -> String {
        let m = sec / 60
        let s = sec % 60
        return m > 0 ? String(format: "%dm %02ds", m, s) : "\(s)s"
    }
}

struct DealCardRow: View {
    let deal: DealItem
    let onOpenDetail: () -> Void
    let onStateChange: (String) -> Void
    let onDelete: () -> Void
    let onOpenLink: () -> Void

    private var scoreColor: Color {
        let s = deal.dealScore ?? 0
        if s >= 80 { return HubTheme.emerald }
        if s >= 60 { return HubTheme.sky }
        return .gray
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image with Score & Drop Badges
            ZStack(alignment: .topLeading) {
                if let imgStr = deal.imageUrl, let url = URL(string: imgStr) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            HubTheme.bg.overlay(Image(systemName: "photo").font(.title2).foregroundStyle(.secondary))
                        }
                    }
                    .frame(height: 185)
                    .clipped()
                } else {
                    HubTheme.bg
                        .frame(height: 125)
                        .overlay(Image(systemName: "tag.fill").font(.title2).foregroundStyle(.secondary))
                }

                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .center)
                    .frame(height: 60)

                HStack {
                    if !deal.isIgnored {
                        HStack(spacing: 4) {
                            Image(systemName: (deal.dealScore ?? 0) >= 80 ? "flame.fill" : "sparkles")
                            Text("Score \(deal.dealScore ?? 50)")
                        }
                        .font(.system(size: 11, weight: .heavy))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(scoreColor.opacity(0.92), in: RoundedRectangle(cornerRadius: 9))
                        .foregroundStyle(.white)
                    } else {
                        Text("Ignoriert")
                            .font(.system(size: 11, weight: .heavy))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.gray.opacity(0.88), in: RoundedRectangle(cornerRadius: 9))
                    }

                    Spacer()

                    if let drop = deal.priceDropEur, drop > 0 {
                        Text("📉 -\(Int(drop.rounded())) € (-\(Int((deal.priceDropPct ?? 0).rounded()))%)")
                            .font(.system(size: 11, weight: .heavy))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(HubTheme.rose.opacity(0.95), in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(.white)
                    }
                }
                .padding(10)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(deal.price)
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(HubTheme.emerald)
                    if let drop = deal.priceDropEur, drop > 0, let initP = deal.initialPriceNum {
                        Text("\(Int(initP.rounded())) €")
                            .font(.caption)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(deal.searchName)
                        .font(.system(size: 10.5, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(HubTheme.sky.opacity(0.16), in: Capsule())
                        .foregroundStyle(HubTheme.sky)
                        .lineLimit(1)
                }

                Text(deal.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .onTapGesture { onOpenDetail() }

                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11))
                        .foregroundStyle(HubTheme.sky)
                    Text("\(deal.location ?? "Umland FFM")\(deal.distance.map { " (\($0))" } ?? "")")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Symbolic Info Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if let ship = deal.shipping, !ship.isEmpty {
                            let isShip = ship.lowercased().contains("versand")
                            pillBadge(icon: "shippingbox.fill", text: ship, color: isShip ? HubTheme.emerald : .gray)
                        }
                        if let rating = deal.sellerInfo?.rating, !rating.isEmpty {
                            pillBadge(icon: "person.badge.shield.checkmark.fill", text: rating, color: rating.contains("TOP") ? HubTheme.emerald : HubTheme.amber)
                        }
                        if let since = deal.sellerInfo?.activeSince {
                            pillBadge(icon: "calendar", text: "Seit \(since)", color: .gray)
                        }
                        if deal.isCommercial == true {
                            pillBadge(icon: "building.2.fill", text: "PRO", color: HubTheme.indigo)
                        }
                    }
                }

                if deal.isIgnored {
                    Text(deal.status.replacingOccurrences(of: "ignored: ", with: "🚫 "))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color(red: 1, green: 0.75, blue: 0.8))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HubTheme.rose.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                }

                if let warns = deal.warnings, !warns.isEmpty {
                    Text(warns.joined(separator: " • "))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(HubTheme.amber)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(HubTheme.amber.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                }

                Divider().overlay(HubTheme.border).padding(.vertical, 2)

                // Footer Action Bar
                HStack(spacing: 8) {
                    iconActionBtn(
                        symbol: deal.effectiveState == "favorite" ? "star.fill" : "star",
                        active: deal.effectiveState == "favorite",
                        activeColor: HubTheme.amber
                    ) {
                        onStateChange(deal.effectiveState == "favorite" ? "new" : "favorite")
                    }

                    iconActionBtn(
                        symbol: deal.effectiveState == "contacted" ? "message.fill" : "message",
                        active: deal.effectiveState == "contacted",
                        activeColor: HubTheme.sky
                    ) {
                        onStateChange(deal.effectiveState == "contacted" ? "new" : "contacted")
                    }

                    iconActionBtn(
                        symbol: "archivebox.fill",
                        active: deal.effectiveState == "archived",
                        activeColor: HubTheme.indigo
                    ) {
                        onStateChange(deal.effectiveState == "archived" ? "new" : "archived")
                    }

                    iconActionBtn(symbol: "info.circle", active: false, activeColor: HubTheme.sky) {
                        onOpenDetail()
                    }

                    Spacer()

                    Button {
                        onOpenLink()
                    } label: {
                        HStack(spacing: 5) {
                            Text("Öffnen")
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.system(size: 12.5, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(LinearGradient(colors: [HubTheme.sky, HubTheme.indigo], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
        }
        .hubCard(cornerRadius: 18, highlight: deal.effectiveState == "favorite" ? HubTheme.amber : nil)
    }

    private func pillBadge(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9.5))
            Text(text).font(.system(size: 10.5, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 7))
        .foregroundStyle(color == .gray ? .secondary : color)
    }

    private func iconActionBtn(symbol: String, active: Bool, activeColor: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 34)
                .background(active ? activeColor.opacity(0.22) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(active ? activeColor.opacity(0.6) : HubTheme.border, lineWidth: 1))
                .foregroundStyle(active ? activeColor : .secondary)
        }
        .buttonStyle(.plain)
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
                    Section("Vollständige Beschreibung") {
                        Text(desc).font(.footnote)
                    }
                }

                Section("Persönliche Notiz") {
                    TextField("Notiz eingeben…", text: $noteText, axis: .vertical)
                        .lineLimit(2...5)
                    Button("💾 Notiz speichern") {
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
                    Button("Aus Datenbank entfernen", role: .destructive) {
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
