import Foundation

/// 当前代理出口的 IP 和大致位置。
struct ExitInfo: Codable, Equatable {
    var ip: String
    var city: String
    var region: String
    var country: String
    var latitude: Double
    var longitude: Double
    var org: String?

    var countryName: String {
        guard !country.isEmpty else { return "" }
        return Locale(identifier: "zh_Hans").localizedString(forRegionCode: country) ?? country
    }

    var displayCity: String {
        if !city.isEmpty { return city }
        if !region.isEmpty { return region }
        return countryName
    }

    /// 例如 "Tokyo，日本"
    var summary: String {
        let c = countryName
        if c.isEmpty || c == displayCity { return displayCity }
        return "\(displayCity)，\(c)"
    }
}

enum ExitIPError: LocalizedError {
    case http(Int, String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "HTTP \(code)：\(body)"
        case .badResponse(let body): return "返回内容里没有位置信息：\(body)"
        }
    }
}

/// 查出口 IP。用 URLSession，默认走系统代理，和 Surge 等工具设置的系统代理一致。
enum ExitIPService {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpAdditionalHeaders = ["User-Agent": "Elsewhere-macOS", "Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    /// 查 IP + 位置（ipinfo.io）。
    static func lookup() async throws -> ExitInfo {
        let (data, response) = try await session.data(from: URL(string: "https://ipinfo.io/json")!)
        let body = String(decoding: data.prefix(300), as: UTF8.self)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ExitIPError.http(http.statusCode, body)
        }
        struct Raw: Decodable {
            let ip: String?
            let city: String?
            let region: String?
            let country: String?
            let loc: String?
            let org: String?
        }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        let parts = (raw.loc ?? "").split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard let ip = raw.ip, parts.count == 2 else { throw ExitIPError.badResponse(body) }
        return ExitInfo(ip: ip, city: raw.city ?? "", region: raw.region ?? "", country: raw.country ?? "",
                        latitude: parts[0], longitude: parts[1], org: raw.org)
    }

    /// 只查 IP，用于后台定时检测出口有没有变（ipify 不限次数，省下 ipinfo 的额度）。
    static func currentIP() async throws -> String {
        for url in ["https://api.ipify.org", "https://ipinfo.io/ip"] {
            if let (data, response) = try? await session.data(from: URL(string: url)!),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                let ip = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !ip.isEmpty, ip.count <= 45 { return ip }
            }
        }
        throw ExitIPError.badResponse("查不到出口 IP")
    }
}
