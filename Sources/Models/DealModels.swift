import Foundation

struct DealStateResponse: Codable {
    let runtime: DealRuntime
    let stats: DealStats
}

struct DealRuntime: Codable {
    let isScanning: Bool
    let scanMode: String?
    let currentSearch: String?
    let scanProgress: String?
    let lastScanAt: String?
    let nextScanInSec: Int?
    let lastDurationSec: Double?
    let lastSummary: String?
    let quietHoursActive: Bool?

    enum CodingKeys: String, CodingKey {
        case isScanning = "is_scanning"
        case scanMode = "scan_mode"
        case currentSearch = "current_search"
        case scanProgress = "scan_progress"
        case lastScanAt = "last_scan_at"
        case nextScanInSec = "next_scan_in_sec"
        case lastDurationSec = "last_duration_sec"
        case lastSummary = "last_summary"
        case quietHoursActive = "quiet_hours_active"
    }
}

struct DealStats: Codable {
    let totalSeen: Int
    let activeDeals: Int
    let totalDeals: Int
    let todayDeals: Int
    let favorites: Int
    let contacted: Int
    let archived: Int
    let ignored: Int
    let priceDrops: Int
    let matchRatePct: Double
    let byCategory: [CategoryStat]?

    enum CodingKeys: String, CodingKey {
        case favorites, contacted, archived, ignored
        case totalSeen = "total_seen"
        case activeDeals = "active_deals"
        case totalDeals = "total_deals"
        case todayDeals = "today_deals"
        case priceDrops = "price_drops"
        case matchRatePct = "match_rate_pct"
        case byCategory = "by_category"
    }
}

struct CategoryStat: Codable, Identifiable {
    let name: String
    let deals: Int
    let ignored: Int
    let avgPrice: Double?
    let minPrice: Double?
    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, deals, ignored
        case avgPrice = "avg_price"
        case minPrice = "min_price"
    }
}

struct DealItem: Codable, Identifiable {
    let adId: String
    let searchName: String
    let title: String
    let price: String
    let priceNum: Double?
    let initialPriceNum: Double?
    let priceDropEur: Double?
    let priceDropPct: Double?
    let location: String?
    let distance: String?
    let distanceKm: Double?
    let url: String
    let imageUrl: String?
    let status: String
    let description: String?
    let attributes: [String: String]?
    let shipping: String?
    let sellerInfo: SellerInfo?
    let dealScore: Int?
    let warnings: [String]?
    let userState: String?
    let notes: String?
    let isCommercial: Bool?
    let createdAt: String?
    let updatedAt: String?

    var id: String { adId }
    var isIgnored: Bool { !status.hasPrefix("notified") }
    var effectiveState: String { userState ?? "new" }

    enum CodingKeys: String, CodingKey {
        case title, price, location, distance, url, status, description, attributes, shipping, warnings, notes
        case adId = "ad_id"
        case searchName = "search_name"
        case priceNum = "price_num"
        case initialPriceNum = "initial_price_num"
        case priceDropEur = "price_drop_eur"
        case priceDropPct = "price_drop_pct"
        case distanceKm = "distance_km"
        case imageUrl = "image_url"
        case sellerInfo = "seller_info"
        case dealScore = "deal_score"
        case userState = "user_state"
        case isCommercial = "is_commercial"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SellerInfo: Codable {
    let type: String?
    let rating: String?
    let activeSince: String?
    let adsOnline: Int?

    enum CodingKeys: String, CodingKey {
        case type, rating
        case activeSince = "active_since"
        case adsOnline = "ads_online"
    }
}

struct DealConfig: Codable {
    var ntfyTopic: String
    var dashboardUrl: String
    var checkIntervalSeconds: Int
    var fetchDetails: Bool?
    var maxDetailFetchesPerCycle: Int?
    var maxDetailFetchesDeep: Int?
    var priceDropMinEur: Double?
    var priceDropMinPct: Double?
    var quietHours: QuietHoursConfig?
    var searches: [SearchRule]

    enum CodingKeys: String, CodingKey {
        case searches
        case ntfyTopic = "ntfy_topic"
        case dashboardUrl = "dashboard_url"
        case checkIntervalSeconds = "check_interval_seconds"
        case fetchDetails = "fetch_details"
        case maxDetailFetchesPerCycle = "max_detail_fetches_per_cycle"
        case maxDetailFetchesDeep = "max_detail_fetches_deep"
        case priceDropMinEur = "price_drop_min_eur"
        case priceDropMinPct = "price_drop_min_pct"
        case quietHours = "quiet_hours"
    }
}

struct QuietHoursConfig: Codable {
    var enabled: Bool
    var start: String
    var end: String
    var bypassMinScore: Int

    enum CodingKeys: String, CodingKey {
        case enabled, start, end
        case bypassMinScore = "bypass_min_score"
    }
}

struct SearchRule: Codable, Identifiable {
    var name: String
    var enabled: Bool?
    var url: String
    var minPrice: Double?
    var maxPrice: Double?
    var conditionMode: String?
    var ignoreWanted: Bool?
    var ignoreCommercial: Bool?
    var requiredKeywords: [String]?
    var negativeKeywords: [String]?
    var titleNegativeKeywords: [String]?
    var maxDistanceKm: Double?

    var id: String { name + "|" + url }
    var isEnabled: Bool { enabled ?? true }

    enum CodingKeys: String, CodingKey {
        case name, enabled, url
        case minPrice = "min_price"
        case maxPrice = "max_price"
        case conditionMode = "condition_mode"
        case ignoreWanted = "ignore_wanted"
        case ignoreCommercial = "ignore_commercial"
        case requiredKeywords = "required_keywords"
        case negativeKeywords = "negative_keywords"
        case titleNegativeKeywords = "title_negative_keywords"
        case maxDistanceKm = "max_distance_km"
    }
}

struct ScanLogEntry: Codable, Identifiable {
    let ts: String
    let level: String
    let msg: String
    var id: String { ts + level + msg }
}
