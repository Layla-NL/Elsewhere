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
    case proxy(String, String)

    var errorDescription: String? {
        switch self {
        case .proxy(let address, let detail): return "无法通过手机代理 \(address) 查询：\(detail)"
        case .http(let code, let body): return "HTTP \(code)：\(body)"
        case .badResponse(let body): return "返回内容里没有位置信息：\(body)"
        }
    }
}

/// 查出口时的代理。nil 表示直接从本机发出（走系统代理，和 Surge 等工具一致）。
/// 填手机代理 App 共享到局域网的 HTTP 代理，查到的就是手机的出口。
struct ExitProxy: Equatable, Hashable {
    let host: String
    let port: Int

    /// 解析 "192.168.1.20:1082"。
    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.lastIndex(of: ":"),
              let port = Int(trimmed[trimmed.index(after: colon)...]), (1...65535).contains(port) else { return nil }
        let host = String(trimmed[..<colon]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        guard !host.isEmpty else { return nil }
        self.host = host
        self.port = port
    }

    var display: String { "\(host):\(port)" }
}

/// 查出口 IP。
enum ExitIPService {
    private static var sessions: [ExitProxy?: URLSession] = [:]
    private static let lock = NSLock()

    private static func session(_ proxy: ExitProxy?) -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let existing = sessions[proxy] { return existing }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpAdditionalHeaders = ["User-Agent": "Elsewhere-macOS", "Accept": "application/json"]
        if let proxy {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: proxy.host,
                kCFNetworkProxiesHTTPPort as String: proxy.port,
                kCFNetworkProxiesHTTPSEnable as String: 1,
                kCFNetworkProxiesHTTPSProxy as String: proxy.host,
                kCFNetworkProxiesHTTPSPort as String: proxy.port,
            ]
        }
        let session = URLSession(configuration: config)
        sessions[proxy] = session
        return session
    }

    private static func data(_ url: String, proxy: ExitProxy?) async throws -> (Data, URLResponse) {
        do {
            return try await session(proxy).data(from: URL(string: url)!)
        } catch let error as URLError where proxy != nil {
            throw ExitIPError.proxy(proxy!.display, error.localizedDescription)
        }
    }

    /// 查 IP + 位置（ipinfo.io）。
    static func lookup(proxy: ExitProxy? = nil) async throws -> ExitInfo {
        let (data, response) = try await data("https://ipinfo.io/json", proxy: proxy)
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
    static func currentIP(proxy: ExitProxy? = nil) async throws -> String {
        for url in ["https://api.ipify.org", "https://ipinfo.io/ip"] {
            if let (data, response) = try? await data(url, proxy: proxy),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                let ip = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !ip.isEmpty, ip.count <= 45 { return ip }
            }
        }
        throw ExitIPError.badResponse("查不到出口 IP")
    }
}
