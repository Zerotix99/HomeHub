import Foundation
import SwiftUI

struct SmartHomeStateResponse: Codable {
    let haOnline: Bool
    let haUrl: String?
    let echoShowOnline: Bool
    let echoShowIp: String?
    let summary: SmartHomeSummary
    let lights: [SmartLightItem]
    let devices: [SmartDeviceItem]
    let scenes: [SmartSceneItem]

    enum CodingKeys: String, CodingKey {
        case summary, lights, devices, scenes
        case haOnline = "ha_online"
        case haUrl = "ha_url"
        case echoShowOnline = "echo_show_online"
        case echoShowIp = "echo_show_ip"
    }
}

struct SmartHomeSummary: Codable {
    let lightsOn: Int
    let lightsTotal: Int
    let devicesOnline: Int
    let devicesTotal: Int
    let powerWatts: Double
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
    var brightness: Int       // 1..100
    var tempK: Int?           // 2200..6500
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

struct SmartDeviceItem: Codable, Identifiable {
    let id: String
    let name: String
    let room: String
    let category: String      // "plug", "display", "speaker", "bridge", "media", "pc_plug"
    let brand: String
    let ip: String?
    let online: Bool
    let isOn: Bool
    let controllable: Bool
    let protectedDevice: Bool
    let subtitle: String
    let icon: String
    let haEntityId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, room, category, brand, ip, online, controllable, subtitle, icon
        case isOn = "is_on"
        case protectedDevice = "protected"
        case haEntityId = "ha_entity_id"
    }
}

struct SmartSceneItem: Codable, Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let colorHex: String
}
