import Foundation
import SwiftUI
import UIKit

enum ConnectionMode: String, CaseIterable, Identifiable {
    case auto = "auto"
    case tailscale = "tailscale"
    case lan = "lan"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return "Auto"
        case .tailscale: return "Tailscale"
        case .lan: return "WLAN (LAN)"
        }
    }
}

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

@MainActor
final class HubClient: ObservableObject {
    // Persisted connection settings
    @AppStorage("pi_tailscale_ip") var piTailscaleIP: String = "100.100.2.103"
    @AppStorage("pi_lan_ip") var piLanIP: String = "192.168.0.87"
    @AppStorage("pc_tailscale_ip") var pcTailscaleIP: String = "100.77.172.23"
    @AppStorage("pc_lan_ip") var pcLanIP: String = "192.168.0.33"
    @AppStorage("connection_mode") var connectionModeRaw: String = ConnectionMode.auto.rawValue

    var connectionMode: ConnectionMode {
        get { ConnectionMode(rawValue: connectionModeRaw) ?? .auto }
        set {
            connectionModeRaw = newValue.rawValue
            objectWillChange.send()
            Task { await resolveActiveHost() }
        }
    }

    // Active resolved Pi host
    @Published var activePiHost: String = "100.100.2.103"
    @Published var activeRouteLabel: String = "Tailscale"
    @Published var isConnected: Bool = false

    // Live JellyControl state
    @Published var jellyStatus: JellyStatusResponse?
    @Published var jellyError: String?

    // Live Deal Radar state
    @Published var dealState: DealStateResponse?
    @Published var deals: [DealItem] = []
    @Published var dealConfig: DealConfig?
    @Published var dealLogs: [ScanLogEntry] = []
    @Published var dealError: String?

    // Anisette Server health
    @Published var anisetteOnline: Bool = false

    // Toast notification
    @Published var toastMessage: String?

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 12
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    var jellyBaseURL: String { "http://\(activePiHost):5050" }
    var dealBaseURL: String { "http://\(activePiHost):8888" }
    var anisetteURL: String { "http://\(activePiHost):6969" }

    var resolvedPcHost: String {
        switch connectionMode {
        case .lan: return pcLanIP
        case .tailscale: return pcTailscaleIP
        case .auto:
            return activePiHost == piLanIP ? pcLanIP : pcTailscaleIP
        }
    }

    func showToast(_ msg: String) {
        withAnimation(.spring(response: 0.3)) {
            toastMessage = msg
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if toastMessage == msg {
                withAnimation(.easeOut(duration: 0.25)) {
                    toastMessage = nil
                }
            }
        }
    }

    func resolveActiveHost() async {
        switch connectionMode {
        case .tailscale:
            activePiHost = piTailscaleIP
            activeRouteLabel = "Tailscale"
            return
        case .lan:
            activePiHost = piLanIP
            activeRouteLabel = "WLAN"
            return
        case .auto:
            // Try Tailscale first (works both home & away), fall back to LAN
            if await probeHost(piTailscaleIP) {
                activePiHost = piTailscaleIP
                activeRouteLabel = "Tailscale"
                isConnected = true
            } else if await probeHost(piLanIP) {
                activePiHost = piLanIP
                activeRouteLabel = "WLAN"
                isConnected = true
            } else {
                isConnected = false
            }
        }
    }

    private func probeHost(_ host: String) async -> Bool {
        guard let url = URL(string: "http://\(host):5050/api/status") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.0
        do {
            let (_, resp) = try await session.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Generic JSON Helpers

    private func getJSON<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        let (data, resp) = try await session.data(from: url)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func sendJSON<B: Encodable, R: Decodable>(_ urlString: String, method: String = "POST", body: B? = nil) async throws -> R {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            req.httpBody = try JSONEncoder().encode(body)
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(R.self, from: data)
    }

    // MARK: - JellyControl API

    func refreshJelly() async {
        do {
            let st: JellyStatusResponse = try await getJSON("\(jellyBaseURL)/api/status?t=\(Int(Date().timeIntervalSince1970))")
            jellyStatus = st
            jellyError = nil
            isConnected = true
        } catch {
            jellyError = "Keine Verbindung zu \(activePiHost):5050"
            if connectionMode == .auto {
                await resolveActiveHost()
            }
        }
    }

    func sendJellyAction(_ path: String, fallbackMsg: String) async {
        Haptics.medium()
        do {
            guard let url = URL(string: "\(jellyBaseURL)\(path)") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            let (data, _) = try await session.data(for: req)
            let res = try? JSONDecoder().decode(ActionResponse.self, from: data)
            Haptics.success()
            showToast(res?.message ?? fallbackMsg)
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await refreshJelly()
        } catch {
            Haptics.error()
            showToast("Verbindungsfehler zum Pi")
        }
    }

    // MARK: - Deal Radar API

    func refreshDealState() async {
        do {
            let st: DealStateResponse = try await getJSON("\(dealBaseURL)/api/state")
            dealState = st
            dealError = nil
            isConnected = true
        } catch {
            dealError = "Deal Radar auf \(activePiHost):8888 nicht erreichbar"
        }
    }

    func fetchDeals(view: String, category: String = "all", query: String = "", sort: String = "newest") async {
        var comps = URLComponents(string: "\(dealBaseURL)/api/deals")
        comps?.queryItems = [
            URLQueryItem(name: "view", value: view),
            URLQueryItem(name: "category", value: category),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "limit", value: "200")
        ]
        guard let urlStr = comps?.url?.absoluteString else { return }
        do {
            let items: [DealItem] = try await getJSON(urlStr)
            deals = items
        } catch {
            dealError = "Fehler beim Laden der Deals"
        }
    }

    func updateDealState(adId: String, userState: String? = nil, notes: String? = nil) async {
        struct Payload: Encodable { let user_state: String?; let notes: String? }
        Haptics.light()
        do {
            let encoded = adId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? adId
            let _: ActionResponse = try await sendJSON(
                "\(dealBaseURL)/api/deals/\(encoded)/state",
                body: Payload(user_state: userState, notes: notes)
            )
            Haptics.success()
            await refreshDealState()
        } catch {
            Haptics.error()
            showToast("Konnte Status nicht speichern")
        }
    }

    func deleteDeal(adId: String) async {
        let encoded = adId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? adId
        guard let url = URL(string: "\(dealBaseURL)/api/deals/\(encoded)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        do {
            let _ = try await session.data(for: req)
            Haptics.success()
            showToast("Inserat entfernt")
            await refreshDealState()
        } catch {
            Haptics.error()
        }
    }

    func triggerDealScan(deep: Bool, searchName: String? = nil) async {
        struct ScanPayload: Encodable { let deep: Bool; let search_name: String?; let max_pages: Int }
        struct ScanResp: Decodable { let ok: Bool?; let triggered: Bool? }
        Haptics.medium()
        do {
            let res: ScanResp = try await sendJSON(
                "\(dealBaseURL)/api/scan",
                body: ScanPayload(deep: deep, search_name: searchName, max_pages: 25)
            )
            if res.triggered == true {
                Haptics.success()
                showToast(deep ? "🔎 Tiefenscan gestartet!" : "⚡ Schnellscan gestartet!")
            } else {
                showToast("⏳ Scan läuft bereits")
            }
            await refreshDealState()
        } catch {
            Haptics.error()
            showToast("Scan-Start fehlgeschlagen")
        }
    }

    func sendTestPush() async {
        do {
            guard let url = URL(string: "\(dealBaseURL)/api/test-ntfy") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            let (_, resp) = try await session.data(for: req)
            if (resp as? HTTPURLResponse)?.statusCode == 200 {
                Haptics.success()
                showToast("🔔 Test-Push an ntfy gesendet!")
            } else {
                Haptics.error()
                showToast("Test-Push fehlgeschlagen")
            }
        } catch {
            Haptics.error()
            showToast("Test-Push fehlgeschlagen")
        }
    }

    func fetchDealConfig() async {
        do {
            dealConfig = try await getJSON("\(dealBaseURL)/api/config")
        } catch {}
    }

    func saveDealConfig(_ cfg: DealConfig) async -> Bool {
        do {
            dealConfig = try await sendJSON("\(dealBaseURL)/api/config", body: cfg)
            Haptics.success()
            return true
        } catch {
            Haptics.error()
            showToast("Speichern fehlgeschlagen")
            return false
        }
    }

    func buildKleinanzeigenURL(query: String, minPrice: Int, maxPrice: Int, radiusKm: Int, category: String) async -> String? {
        struct Req: Encodable { let query: String; let min_price: Int; let max_price: Int; let radius_km: Int; let category: String }
        struct Res: Decodable { let url: String }
        do {
            let res: Res = try await sendJSON(
                "\(dealBaseURL)/api/build-url",
                body: Req(query: query, min_price: minPrice, max_price: maxPrice, radius_km: radiusKm, category: category)
            )
            return res.url
        } catch {
            return nil
        }
    }

    func updateQuickPrice(index: Int, minPrice: Double, maxPrice: Double) async -> Bool {
        struct Req: Encodable { let index: Int; let min_price: Double; let max_price: Double; let sync_url: Bool }
        do {
            dealConfig = try await sendJSON("\(dealBaseURL)/api/searches/quick-price", body: Req(index: index, min_price: minPrice, max_price: maxPrice, sync_url: true))
            Haptics.success()
            showToast("💰 Preisspanne gespeichert!")
            return true
        } catch {
            Haptics.error()
            showToast("Ungültige Preisspanne")
            return false
        }
    }

    func deleteSearchRule(index: Int, deleteAds: Bool) async -> Bool {
        guard let url = URL(string: "\(dealBaseURL)/api/searches/\(index)?delete_ads=\(deleteAds ? "1" : "0")") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        struct DelResp: Decodable { let ok: Bool; let config: DealConfig }
        do {
            let (data, resp) = try await session.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let parsed = try JSONDecoder().decode(DelResp.self, from: data)
            dealConfig = parsed.config
            Haptics.success()
            showToast("🗑 Gerät gelöscht")
            await refreshDealState()
            return true
        } catch {
            Haptics.error()
            showToast("Löschen fehlgeschlagen")
            return false
        }
    }

    func fetchDealLogs() async {
        dealLogs = (try? await getJSON("\(dealBaseURL)/api/logs")) ?? []
    }

    func checkAnisetteHealth() async {
        guard let url = URL(string: anisetteURL) else { anisetteOnline = false; return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.0
        do {
            let (_, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            anisetteOnline = (200...299).contains(code)
        } catch {
            anisetteOnline = false
        }
    }
}
