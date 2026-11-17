import Foundation

struct JellyStatusResponse: Codable {
    let pcOnline: Bool
    let latencyMs: Double?
    let daemonOnline: Bool
    let daemonData: DaemonData?
    let jellyfinInfo: JellyfinInfo?
    let powerHistory: [PowerSample]?
    let plug: PlugStatus?
    let piStats: PiStats?
    let recentLogs: [String]?
    let terminalText: String?
    let config: JellyConfig?
    let timestamp: Int?

    enum CodingKeys: String, CodingKey {
        case pcOnline = "pc_online"
        case latencyMs = "latency_ms"
        case daemonOnline = "daemon_online"
        case daemonData = "daemon_data"
        case jellyfinInfo = "jellyfin_info"
        case powerHistory = "power_history"
        case plug
        case piStats = "pi_stats"
        case recentLogs = "recent_logs"
        case terminalText = "terminal_text"
        case config
        case timestamp
    }
}

struct DaemonData: Codable {
    let status: String?
    let hostname: String?
    let serverMode: Bool?
    let nordvpn: Bool?
    let nordvpnIp: String?
    let qbittorrent: Bool?
    let ssh: Bool?
    let sunshine: Bool?
    let rustdesk: Bool?
    let jellyfin: Bool?
    let radarr: Bool?
    let sonarr: Bool?
    let prowlarr: Bool?
    let tailscale: Bool?
    let uptimeSeconds: Int?
    let hardware: HardwareTelemetry?
    let rgbKilled: Bool?
    let monitorsAttached: Int?
    let screenLocked: Bool?

    enum CodingKeys: String, CodingKey {
        case status, hostname, nordvpn, qbittorrent, ssh, sunshine, rustdesk, jellyfin, radarr, sonarr, prowlarr, tailscale, hardware
        case serverMode = "server_mode"
        case nordvpnIp = "nordvpn_ip"
        case uptimeSeconds = "uptime_seconds"
        case rgbKilled = "rgb_killed"
        case monitorsAttached = "monitors_attached"
        case screenLocked = "screen_locked"
    }
}

struct HardwareTelemetry: Codable {
    let cpuPct: Double?
    let cpuPowerW: Double?
    let gpuPowerW: Double?
    let gpuTempC: Double?
    let ramUsedGb: Double?
    let ramTotalGb: Double?
    let ramPct: Double?
    let estSystemW: Double?

    enum CodingKeys: String, CodingKey {
        case cpuPct = "cpu_pct"
        case cpuPowerW = "cpu_power_w"
        case gpuPowerW = "gpu_power_w"
        case gpuTempC = "gpu_temp_c"
        case ramUsedGb = "ram_used_gb"
        case ramTotalGb = "ram_total_gb"
        case ramPct = "ram_pct"
        case estSystemW = "est_system_w"
    }
}

struct JellyfinInfo: Codable {
    let version: String?
    let serverName: String?
    let product: String?

    enum CodingKeys: String, CodingKey {
        case version, product
        case serverName = "server_name"
    }
}

struct PowerSample: Codable, Identifiable {
    let t: Int
    let w: Double
    var id: Int { t }
}

struct PlugStatus: Codable {
    let success: Bool?
    let name: String?
    let ip: String?
    let state: Bool?
    let online: Bool?
}

struct PiStats: Codable {
    let tempC: Double?
    let uptime: String?
    let load1m: Double?
    let ramPct: Int?
    let ramUsedMb: Int?
    let ramTotalMb: Int?

    enum CodingKeys: String, CodingKey {
        case uptime
        case tempC = "temp_c"
        case load1m = "load_1m"
        case ramPct = "ram_pct"
        case ramUsedMb = "ram_used_mb"
        case ramTotalMb = "ram_total_mb"
    }
}

struct JellyConfig: Codable {
    let pcName: String?
    let pcIp: String?
    let pcTailscaleIp: String?
    let jellyfinPort: Int?
    let qbittorrentPort: Int?
    let radarrPort: Int?
    let sonarrPort: Int?
    let prowlarrPort: Int?
    let kwhPriceEur: Double?

    enum CodingKeys: String, CodingKey {
        case pcName = "pc_name"
        case pcIp = "pc_ip"
        case pcTailscaleIp = "pc_tailscale_ip"
        case jellyfinPort = "jellyfin_port"
        case qbittorrentPort = "qbittorrent_port"
        case radarrPort = "radarr_port"
        case sonarrPort = "sonarr_port"
        case prowlarrPort = "prowlarr_port"
        case kwhPriceEur = "kwh_price_eur"
    }
}

struct ActionResponse: Codable {
    let ok: Bool?
    let message: String?
}
