import Foundation

/// 一台通过 CoreDevice 识别到的真机。
struct PhoneDevice: Identifiable, Equatable {
    /// 传给 `--device` 的标识（优先 UDID）。
    let id: String
    let name: String
    let model: String
    let osVersion: String
    let platform: String
    let paired: Bool
    /// nil 表示 devicectl 没给出这个信息。
    let developerMode: Bool?
    /// `devicectl list devices` 表格里的 State 列，例如 "available (paired)"。
    let stateText: String
    let tunnelConnected: Bool
    /// 由哪个引擎控制这台设备。
    var engine: EngineKind = .xcode
    /// 内置引擎下的连接方式："usb" 或 "network"。
    var connection: String? = nil
    /// 是否开启了无线连接（访达里的「连接 Wi-Fi 时显示此 iPhone」）；nil 表示不知道。
    var wirelessEnabled: Bool? = nil

    var isWireless: Bool { connection == "network" }

    var reachable: Bool {
        if tunnelConnected { return true }
        let s = stateText.lowercased()
        if s.contains("unavailable") || s.contains("disconnected") { return false }
        return s.contains("available") || s.contains("connected")
    }

    /// 「iPhone」「iPad」这样的类别名，用在提示文字里。
    var kind: String {
        model.hasPrefix("iPad") ? "iPad" : "iPhone"
    }

    var subtitle: String {
        var parts: [String] = []
        if !model.isEmpty { parts.append(model) }
        if !osVersion.isEmpty { parts.append("\(platform.isEmpty ? "iOS" : platform) \(osVersion)") }
        if isWireless { parts.append("无线") }
        return parts.joined(separator: " · ")
    }
}

enum DeviceStatus: Equatable {
    case checking
    case toolsMissing(String)
    case listFailed(String)
    case noDevice
    case notTrusted(PhoneDevice)
    case developerModeOff(PhoneDevice)
    case unreachable(PhoneDevice)
    case ready(PhoneDevice)

    var device: PhoneDevice? {
        switch self {
        case .notTrusted(let d), .developerModeOff(let d), .unreachable(let d), .ready(let d): return d
        default: return nil
        }
    }

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var badge: String {
        switch self {
        case .checking: return "检查中"
        case .toolsMissing: return "缺少 Xcode"
        case .listFailed: return "出错"
        case .noDevice, .unreachable: return "未连接"
        case .notTrusted: return "未信任"
        case .developerModeOff: return "需开发者模式"
        case .ready: return "已连接"
        }
    }

    /// 没准备好时给出的原因和处理方法。
    var hint: String? {
        switch self {
        case .checking, .ready:
            return nil
        case .toolsMissing:
            return "未找到 Xcode。可在设置中将定位方式改为「自动」。"
        case .listFailed(let output):
            return "无法读取设备。\(output)"
        case .noDevice:
            return "用数据线连接 iPhone 或 iPad。"
        case .unreachable(let d):
            return "连接并解锁 \(d.kind)。"
        case .notTrusted(let d):
            return "解锁 \(d.kind)，然后轻点「信任」。"
        case .developerModeOff(let d):
            return "在 \(d.kind) 上打开「设置」>「隐私与安全性」>「开发者模式」，然后重新启动。"
        }
    }
}

/// 对 `xcrun devicectl` 的封装。
enum DeviceService {
    static let xcrun = "/usr/bin/xcrun"

    static func checkTools() async -> CommandResult {
        await Shell.run(xcrun, ["--find", "devicectl"], timeout: 30)
    }

    enum ListError: Error {
        case failed(String)
    }

    /// 列出所有已知的 iPhone / iPad 真机。
    static func listPhones() async throws -> [PhoneDevice] {
        let jsonURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("elsewhere-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: jsonURL) }

        let result = await Shell.run(xcrun, ["devicectl", "list", "devices", "--quiet", "--json-output", jsonURL.path], timeout: 30)
        guard result.ok, let data = try? Data(contentsOf: jsonURL) else {
            throw ListError.failed(result.output)
        }
        var phones = parse(json: data)
        guard !phones.isEmpty else { return [] }

        // JSON 里没有直接的「现在能不能连上」字段，用表格里的 State 列补上。
        let states = await stateColumn()
        phones = phones.map { p in
            PhoneDevice(id: p.id, name: p.name, model: p.model, osVersion: p.osVersion, platform: p.platform,
                        paired: p.paired, developerMode: p.developerMode,
                        stateText: states[p.id] ?? p.stateText, tunnelConnected: p.tunnelConnected)
        }
        return phones
    }

    /// 读取 State 列，返回 [UDID: State]。
    private static func stateColumn() async -> [String: String] {
        var result = await Shell.run(xcrun, [
            "devicectl", "list", "devices",
            "--columns", "properties.hardware.udid", "State",
            "--hide-default-columns", "--hide-headers",
        ], timeout: 30)
        if !result.ok {
            // 老版本 devicectl 不支持自定义列，退回默认表格。
            result = await Shell.run(xcrun, ["devicectl", "list", "devices"], timeout: 30)
        }
        var map: [String: String] = [:]
        let idPattern = try! NSRegularExpression(pattern: "\\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}\\b|\\b[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\\b|\\b[0-9a-f]{40}\\b")
        let statePattern = try! NSRegularExpression(pattern: "(unavailable|disconnected|available(?: \\([^)]*\\))?|connected|connecting|paired)", options: [.caseInsensitive])
        for line in result.stdout.split(separator: "\n").map(String.init) {
            let range = NSRange(line.startIndex..., in: line)
            guard let idMatch = idPattern.firstMatch(in: line, range: range),
                  let idRange = Range(idMatch.range, in: line) else { continue }
            let id = String(line[idRange])
            if let sMatch = statePattern.firstMatch(in: line, range: range), let sRange = Range(sMatch.range, in: line) {
                map[id] = String(line[sRange])
            }
        }
        return map
    }

    static func parse(json data: Data) -> [PhoneDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = root["result"] as? [String: Any],
              let devices = result["devices"] as? [[String: Any]] else { return [] }

        return devices.compactMap { device -> PhoneDevice? in
            let props = device["properties"] as? [String: Any] ?? [:]
            let hardware = props["hardware"] as? [String: Any] ?? device["hardwareProperties"] as? [String: Any] ?? [:]
            let connection = props["connection"] as? [String: Any] ?? [:]
            let legacyConnection = device["connectionProperties"] as? [String: Any] ?? [:]
            let state = props["state"] as? [String: Any] ?? [:]
            let legacyDevice = device["deviceProperties"] as? [String: Any] ?? [:]
            let software = props["software"] as? [String: Any] ?? [:]

            guard (hardware["reality"] as? String) == "physical" else { return nil }
            let type = hardware["deviceType"] as? String ?? ""
            guard type == "iPhone" || type == "iPad" else { return nil }

            let id = hardware["udid"] as? String ?? device["identifier"] as? String ?? ""
            guard !id.isEmpty else { return nil }

            let name = state["name"] as? String ?? legacyDevice["name"] as? String ?? type
            let model = hardware["marketingName"] as? String ?? hardware["productType"] as? String ?? type
            var os = ""
            if let v = software["osVersionNumber"] as? [String: Any], let s = v["stringValue"] as? String { os = s }
            else if let s = legacyDevice["osVersionNumber"] as? String { os = s }
            let platform = hardware["platform"] as? String ?? ""

            let pairing = connection["pairingState"] as? String ?? legacyConnection["pairingState"] as? String ?? ""
            let tunnel = legacyConnection["tunnelState"] as? String ?? connection["state"] as? String ?? ""
            let devMode = developerMode(state["developerModeStatus"]) ?? developerMode(legacyDevice["developerModeStatus"])

            return PhoneDevice(id: id, name: name, model: model, osVersion: os, platform: platform,
                               paired: pairing == "paired", developerMode: devMode,
                               stateText: tunnel, tunnelConnected: tunnel == "connected")
        }
    }

    private static func developerMode(_ value: Any?) -> Bool? {
        if let s = value as? String {
            switch s.lowercased() {
            case "enabled": return true
            case "disabled": return false
            default: return nil
            }
        }
        if let d = value as? [String: Any] {
            if d["enabled"] != nil { return true }
            if d["disabled"] != nil { return false }
        }
        return nil
    }

    /// 经纬度用 `--latitude=值` 的写法，负数才不会被当成参数。
    static func setLocation(device: String, latitude: Double, longitude: Double) async -> CommandResult {
        await Shell.run(xcrun, [
            "devicectl", "device", "simulate", "location", "coordinate",
            "--device", device,
            "--latitude=\(format(latitude))",
            "--longitude=\(format(longitude))",
            "--timeout", "60",
        ], timeout: 75)
    }

    static func clearLocation(device: String) async -> CommandResult {
        await Shell.run(xcrun, [
            "devicectl", "device", "simulate", "location", "clear",
            "--device", device,
            "--timeout", "60",
        ], timeout: 75)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
