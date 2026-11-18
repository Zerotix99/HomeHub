import Foundation
import SwiftUI

struct SmartHomeStateResponse: Codable {
    let haOnline: Bool
    let haUrl: String?
    let echoShowOnline: Bool
    let summary: SmartHomeSummary
    let security: SmartSecurityStatus
    let cover: SmartCoverControl
    let climate: SmartClimateControl
    let lights: [SmartLightItem]
    let plugs: [SmartPlugEnergyItem]
    let mediaPlayers: [SmartMediaItem]
    let automations: [SmartAutomationItem]

    enum CodingKeys: String, CodingKey {
        case summary, security, cover, climate, lights, plugs, automations
        case haOnline = "ha_online"
        case haUrl = "ha_url"
        case echoShowOnline = "echo_show_online"
        case mediaPlayers = "media_players"
    }
}

struct SmartHomeSummary: Codable {
    let lightsOn: Int
    let lightsTotal: Int
    let plugsOn: Int
    let plugsTotal: Int
    let powerWatts: Double
    let monthKwh: Double
}

struct SmartSecurityStatus: Codable {
    let doorOpen: Bool
    let windowOpen: Bool
    let currentTempC: Double
    let pcOnline: Bool
    let pcMode: String
    let pcWatts: Int

    enum CodingKeys: String, CodingKey {
        case doorOpen = "door_open"
        case windowOpen = "window_open"
        case currentTempC = "current_temp_c"
        case pcOnline = "pc_online"
        case pcMode = "pc_mode"
        case pcWatts = "pc_watts"
    }
}

struct SmartCoverControl: Codable {
    let entityId: String
    let name: String
    let room: String
    let state: String
    let position: Int
    let online: Bool

    enum CodingKeys: String, CodingKey {
        case name, room, state, position, online
        case entityId = "entity_id"
    }
}

struct SmartClimateControl: Codable {
    let entityId: String
    let name: String
    let room: String
    let hvacMode: String
    let currentTemp: Double
    let targetTemp: Double
    let minTemp: Double
    let maxTemp: Double
    let online: Bool

    enum CodingKeys: String, CodingKey {
        case name, room, online
        case entityId = "entity_id"
        case hvacMode = "hvac_mode"
        case currentTemp = "current_temp"
        case targetTemp = "target_temp"
        case minTemp = "min_temp"
        case maxTemp = "max_temp"
    }

    var isHeating: Bool { hvacMode == "heat" }
}

struct SmartLightItem: Codable, Identifiable {
    let id: String
    let name: String
    let room: String
    let ip: String
    let mac: String?
    let brand: String
    let online: Bool
    var isOn: Bool
    var brightness: Int
    var tempK: Int?
    var sceneId: Int?
    var sceneName: String?
    var r: Int?
    var g: Int?
    var b: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, room, ip, mac, brand, online, brightness, r, g, b
        case isOn = "is_on"
        case tempK = "temp_k"
        case sceneId = "scene_id"
        case sceneName = "scene_name"
    }

    var accentColor: Color {
        guard isOn else { return .gray }
        if let r, let g, let b, (r + g + b) > 30 {
            return Color(
                red: min(1.0, Double(r) / 255.0 + 0.15),
                green: min(1.0, Double(g) / 255.0 + 0.15),
                blue: min(1.0, Double(b) / 255.0 + 0.15)
            )
        }
        return HubTheme.amber
    }
}

struct PlugDayConsumption: Codable, Identifiable {
    let date: String
    let wh: Int
    var id: String { date }
}

struct SmartPlugEnergyItem: Codable, Identifiable {
    let id: String
    let name: String
    let room: String
    let ip: String
    let icon: String
    let online: Bool
    let isOn: Bool
    let powerW: Double
    let voltageV: Double
    let todayWh: Int
    let monthKwh: Double
    let history: [PlugDayConsumption]
    let haEntityId: String

    enum CodingKeys: String, CodingKey {
        case id, name, room, ip, icon, online, history
        case isOn = "is_on"
        case powerW = "power_w"
        case voltageV = "voltage_v"
        case todayWh = "today_wh"
        case monthKwh = "month_kwh"
        case haEntityId = "ha_entity_id"
    }
}

struct SmartMediaItem: Codable, Identifiable {
    let id: String
    let name: String
    let room: String
    let brand: String
    let icon: String
    let state: String
    let subtitle: String
    let volumePct: Int
    let isPlaying: Bool
    let isOn: Bool
    let haEntityId: String

    enum CodingKeys: String, CodingKey {
        case id, name, room, brand, icon, state, subtitle
        case volumePct = "volume_pct"
        case isPlaying = "is_playing"
        case isOn = "is_on"
        case haEntityId = "ha_entity_id"
    }
}

struct SmartAutomationItem: Codable, Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, subtitle, icon
        case isEnabled = "is_enabled"
    }
}

struct HubNotificationItem: Codable, Identifiable {
    let id: String
    let title: String
    let body: String
    let tag: String?
    let url: String?
    let timestamp: Double
}

struct HubNotificationsResponse: Codable {
    let ok: Bool
    let notifications: [HubNotificationItem]
}

