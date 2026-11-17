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

struct JITAppEntry: Codable, Identifiable {
    let name: String
    let bundle: String
    let pid: Int
    var id: String { bundle }
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

    @Published var activePiHost: String = "100.100.2.103"
    @Published var activeRouteLabel: String = "Tailscale"
    @Published var isConnected: Bool = false

    // JellyControl state
    @Published var jellyStatus: JellyStatusResponse?
    @Published var jellyError: String?

    // Smart Home state (HomeKit / HA / WiZ / TECHO5)
    @Published var smartHomeState: SmartHomeStateResponse?

    // Deal Radar state
    @Published var dealState: DealStateResponse?
    @Published var deals: [DealItem] = []
    @Published var dealConfig: DealConfig?
    @Published var dealLogs: [ScanLogEntry] = []
    @Published var dealError: String?

    // SideStore & SideJITServer state
    @Published var anisetteOnline: Bool = false
    @Published var sideJITOnline: Bool = false
    @Published var sideJITVersion: String = ""
    @Published var sideJITApps: [JITAppEntry] = []
    @Published var isRefreshingJIT: Bool = false

    // Toast
    @Published var toastMessage: String?

    let deviceUDID: String = "00008150-0011515234DA401C"
    let githubLatestIPAURL: String = "https://github.com/Zerotix99/HomeHub/releases/latest/download/HomeHub.ipa"

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 6
        cfg.timeoutIntervalForResource = 15
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()

    var jellyBaseURL: String { "http://\(activePiHost):5050" }
    var dealBaseURL: String { "http://\(activePiHost):8888" }
    var anisetteURL: String { "http://\(activePiHost):6969" }
    var sideJITURL: String { "http://\(activePiHost):9191" }

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
            showToast("🗑 Inserat entfernt")
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

    // MARK: - Anisette & SideJITServer API

    func checkAnisetteHealth() async {
        guard let url = URL(string: anisetteURL) else { anisetteOnline = false; return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.5
        do {
            let (_, resp) = try await session.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            anisetteOnline = (200...299).contains(code)
        } catch {
            anisetteOnline = false
        }
    }

    func checkSideJIT() async {
        struct VerResp: Decodable { let pymobiledevice3: String?; let SideJITServer: String? }
        do {
            let ver: VerResp = try await getJSON("\(sideJITURL)/ver/")
            sideJITOnline = true
            sideJITVersion = "v\(ver.SideJITServer ?? "1.4") (pymd3 \(ver.pymobiledevice3 ?? ""))"
            await loadSideJITApps(endpoint: "")
        } catch {
            sideJITOnline = false
        }
    }

    func refreshSideJITDevices() async {
        isRefreshingJIT = true
        defer { isRefreshingJIT = false }
        Haptics.medium()
        await loadSideJITApps(endpoint: "/re/")
        showToast(sideJITApps.isEmpty ? "🔄 JIT-Geräte gesucht (Display entsperren!)" : "✅ \(sideJITApps.count) JIT-Apps bereit!")
    }

    private func loadSideJITApps(endpoint: String) async {
        guard let url = URL(string: "\(sideJITURL)\(endpoint)") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12.0
        do {
            let (data, _) = try await session.data(for: req)
            if let dict = try? JSONDecoder().decode([String: [JITAppEntry]].self, from: data) {
                sideJITApps = dict.values.flatMap { $0 }
            }
        } catch {}
    }

    func enableJIT(for app: JITAppEntry) async {
        Haptics.medium()
        let encoded = app.bundle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? app.bundle
        guard let url = URL(string: "\(sideJITURL)/\(deviceUDID)/\(encoded)/") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15.0
        do {
            let (data, _) = try await session.data(for: req)
            let txt = String(data: data, encoding: .utf8) ?? "JIT aktiviert!"
            Haptics.success()
            showToast("⚡ \(txt.replacingOccurrences(of: "\"", with: ""))")
        } catch {
            Haptics.error()
            showToast("JIT fehlgeschlagen – iPhone entsperrt?")
        }
    }

    // MARK: - Smart Home API (HomeKit / HA / WiZ / TECHO5)

    func refreshSmartHome() async {
        do {
            let st: SmartHomeStateResponse = try await getJSON("\(jellyBaseURL)/api/smarthome?t=\(Int(Date().timeIntervalSince1970))")
            smartHomeState = st
            isConnected = true
        } catch {}
    }

    func controlSmartLight(
        id: String,
        state: Bool,
        brightness: Int? = nil,
        tempK: Int? = nil,
        sceneId: Int? = nil,
        rgb: (Int, Int, Int)? = nil
    ) async {
        struct LightReq: Encodable {
            let id: String
            let state: Bool
            let brightness: Int?
            let temp_k: Int?
            let scene_id: Int?
            let r: Int?
            let g: Int?
            let b: Int?
        }
        Haptics.light()
        do {
            let _: ActionResponse = try await sendJSON(
                "\(jellyBaseURL)/api/smarthome/light",
                body: LightReq(
                    id: id,
                    state: state,
                    brightness: brightness,
                    temp_k: tempK,
                    scene_id: sceneId,
                    r: rgb?.0,
                    g: rgb?.1,
                    b: rgb?.2
                )
            )
            await refreshSmartHome()
        } catch {
            Haptics.error()
            showToast("Lampen-Steuerung fehlgeschlagen")
        }
    }

    func triggerSmartScene(_ sceneId: String) async {
        struct SceneReq: Encodable { let scene: String }
        Haptics.medium()
        do {
            let res: ActionResponse = try await sendJSON(
                "\(jellyBaseURL)/api/smarthome/scene",
                body: SceneReq(scene: sceneId)
            )
            Haptics.success()
            showToast(res.message ?? "✨ Szene aktiviert!")
            await refreshSmartHome()
            await refreshJelly()
        } catch {
            Haptics.error()
            showToast("Szene konnte nicht aktiviert werden")
        }
    }

    func toggleSmartDevice(_ dev: SmartDeviceItem) async {
        if dev.protectedDevice {
            Haptics.warning()
            showToast("🔒 PC-Steckdose ist vor versehentlichem Schalten geschützt!")
            return
        }
        struct DevReq: Encodable {
            let id: String
            let ha_entity_id: String?
            let category: String
            let state: Bool
        }
        Haptics.medium()
        do {
            let res: ActionResponse = try await sendJSON(
                "\(jellyBaseURL)/api/smarthome/device",
                body: DevReq(id: dev.id, ha_entity_id: dev.haEntityId, category: dev.category, state: !dev.isOn)
            )
            Haptics.success()
            if let msg = res.message { showToast(msg) }
            await refreshSmartHome()
        } catch {
            Haptics.error()
            showToast("Gerät nicht schaltbar")
        }
    }
}
