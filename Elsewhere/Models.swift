import Foundation
import CoreLocation

/// 界面实际用的语言：跟随系统，只有简体中文和英文，其他语言显示英文。
enum AppLanguage {
    static var locale: Locale { Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en") }
    static var isChinese: Bool { locale.language.languageCode == .chinese }
}

/// 一个可以一键切过去的地点。
struct Place: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var coordinateText: String { Self.format(latitude, longitude) }

    static func format(_ latitude: Double, _ longitude: Double) -> String {
        String(format: "%.4f, %.4f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }

    func isSameSpot(latitude lat: Double, longitude lon: Double) -> Bool {
        abs(latitude - lat) < 0.0001 && abs(longitude - lon) < 0.0001
    }

    static let defaults: [Place] = [
        Place(name: String(localized: "柏林"), latitude: 52.5200, longitude: 13.4050),
        Place(name: String(localized: "法兰克福"), latitude: 50.1109, longitude: 8.6821),
        Place(name: String(localized: "伦敦"), latitude: 51.5074, longitude: -0.1278),
        Place(name: String(localized: "巴黎"), latitude: 48.8566, longitude: 2.3522),
        Place(name: String(localized: "阿姆斯特丹"), latitude: 52.3676, longitude: 4.9041),
        Place(name: String(localized: "纽约"), latitude: 40.7580, longitude: -73.9855),
        Place(name: String(localized: "洛杉矶"), latitude: 34.0522, longitude: -118.2437),
        Place(name: String(localized: "旧金山"), latitude: 37.7749, longitude: -122.4194),
        Place(name: String(localized: "东京"), latitude: 35.6812, longitude: 139.7671),
        Place(name: String(localized: "香港"), latitude: 22.2800, longitude: 114.1588),
        Place(name: String(localized: "新加坡"), latitude: 1.2834, longitude: 103.8607),
    ]
}

enum LocationSource: String, Codable {
    case exitIP, city, custom

    var label: String {
        switch self {
        case .exitIP: return String(localized: "跟随出口")
        case .city: return String(localized: "常用城市")
        case .custom: return String(localized: "自定义")
        }
    }
}

/// 最近一次改到的位置，App 重启后仍然保留。
struct AppliedLocation: Codable, Equatable {
    var name: String
    var latitude: Double
    var longitude: Double
    var date: Date
    var source: LocationSource
    var ip: String?
    var deviceName: String
    /// 改的是哪台设备（UDID）。旧版本存的记录里没有。
    var deviceID: String?
    /// 同时修改多台设备时，所有改成功的设备。
    var deviceIDs: [String]?

    /// 这次修改涉及的设备。
    var devices: [String] { deviceIDs ?? deviceID.map { [$0] } ?? [] }
}

/// 实际控制某台设备的引擎。
enum EngineKind: String, Codable {
    /// App 内置的组件，不需要 Xcode。
    case builtIn
    /// Xcode 自带的 devicectl。
    case xcode
}

/// 设置里的「定位方式」。
enum EngineMode: String, Codable, CaseIterable, Identifiable {
    case auto, builtIn, xcode
    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return String(localized: "自动")
        case .builtIn: return String(localized: "内置")
        case .xcode: return "Xcode"
        }
    }
}

/// 代理出口变化时怎么处理。
enum ExitWatchMode: String, Codable, CaseIterable, Identifiable {
    case off, notify, auto
    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return String(localized: "不检测")
        case .notify: return String(localized: "提醒我")
        case .auto: return String(localized: "自动改")
        }
    }
}

struct Feedback: Identifiable, Equatable {
    enum Kind { case success, failure, info }
    let id = UUID()
    var kind: Kind
    var title: String
    var detail: String?
}
