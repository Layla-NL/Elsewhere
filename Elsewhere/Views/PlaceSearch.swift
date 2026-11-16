import MapKit
import SwiftUI

/// 地名搜索：输入时给出联想，选中后解析成坐标。
///
/// Apple 地图在国区 Mac 上用的是高德数据，海外地名几乎搜不到，所以再并上
/// OpenStreetMap：输入时用 Photon 联想（英文名准），回车时用 Nominatim（中文名也准）。
@MainActor
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = "" {
        didSet {
            osmTask?.cancel()
            let text = query.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                clear()
            } else {
                completer.queryFragment = query
                osmTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    let found = (try? await OpenStreetMap.suggest(text)) ?? []
                    guard !Task.isCancelled, let self, self.query.trimmingCharacters(in: .whitespaces) == text else { return }
                    self.osmResults = found
                }
            }
        }
    }
    @Published var results: [MKLocalSearchCompletion] = []
    /// OpenStreetMap 的联想结果，坐标是 GPS（WGS-84）。
    @Published var osmResults: [OSMPlace] = []
    @Published var searching = false

    var hasSuggestions: Bool { !results.isEmpty || !osmResults.isEmpty }

    private let completer = MKLocalSearchCompleter()
    private var osmTask: Task<Void, Never>?

    func clear() {
        osmTask?.cancel()
        results = []
        osmResults = []
    }

    /// 回车时用：Nominatim 能认中文的海外地名。
    func lookUpOSM(_ text: String) async -> OSMPlace? {
        searching = true
        defer { searching = false }
        return try? await OpenStreetMap.search(text).first
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = Array(completer.results.prefix(6))
        Task { @MainActor in
            guard !self.query.isEmpty else { return }
            self.results = items
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.results = [] }
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> (String, CLLocationCoordinate2D)? {
        await run(MKLocalSearch.Request(completion: completion), fallbackName: completion.title)
    }

    func resolve(text: String) async -> (String, CLLocationCoordinate2D)? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        return await run(request, fallbackName: text)
    }

    private func run(_ request: MKLocalSearch.Request, fallbackName: String) async -> (String, CLLocationCoordinate2D)? {
        searching = true
        defer { searching = false }
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else { return nil }
        clear()
        return (item.name ?? fallbackName, Geo.coordinate(of: item))
    }
}

/// OpenStreetMap 上的一个地点。坐标是 GPS（WGS-84）。
struct OSMPlace: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var detail: String
    var latitude: Double
    var longitude: Double
}

/// OpenStreetMap 的免费地名服务。按它们的使用规范带上 User-Agent，联想有防抖，回车才查 Nominatim。
enum OpenStreetMap {
    private static let userAgent = "Elsewhere/1.0 (macOS menu-bar location tool)"

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(AppLanguage.isChinese ? "zh-CN,zh;q=0.9,en;q=0.8" : "en,zh-CN;q=0.5", forHTTPHeaderField: "Accept-Language")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    /// Photon：适合边输边查。
    static func suggest(_ text: String, limit: Int = 5) async throws -> [OSMPlace] {
        var parts = URLComponents(string: "https://photon.komoot.io/api/")!
        parts.queryItems = [URLQueryItem(name: "q", value: text), URLQueryItem(name: "limit", value: String(limit))]
        struct Response: Decodable {
            struct Feature: Decodable {
                struct Geometry: Decodable { let coordinates: [Double] }
                let geometry: Geometry
                let properties: [String: JSONValue]
            }
            let features: [Feature]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: try await get(parts.url!))
        return decoded.features.compactMap { feature in
            let p = feature.properties
            guard feature.geometry.coordinates.count == 2, let name = p["name"]?.string else { return nil }
            let detail = [p["city"]?.string ?? p["county"]?.string, p["state"]?.string, p["country"]?.string]
                .compactMap { $0 }
                .filter { $0 != name }
                .joined(separator: " · ")
            return OSMPlace(name: name, detail: detail,
                            latitude: feature.geometry.coordinates[1], longitude: feature.geometry.coordinates[0])
        }
    }

    /// Nominatim：中文名准，但不许当联想用，只在回车时调用。
    static func search(_ text: String, limit: Int = 3) async throws -> [OSMPlace] {
        var parts = URLComponents(string: "https://nominatim.openstreetmap.org/search")!
        parts.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "accept-language", value: AppLanguage.isChinese ? "zh-CN" : "en"),
        ]
        struct Item: Decodable {
            let name: String?
            let display_name: String
            let lat: String
            let lon: String
        }
        let items = try JSONDecoder().decode([Item].self, from: try await get(parts.url!))
        return items.compactMap { item in
            guard let lat = Double(item.lat), let lon = Double(item.lon) else { return nil }
            // 名字里常有「洛杉矶;洛杉磯」这种多写法，取第一个。
            let name = (item.name?.isEmpty == false ? item.name! : item.display_name)
                .split(separator: ";").first.map(String.init) ?? item.display_name
            return OSMPlace(name: name, detail: item.display_name, latitude: lat, longitude: lon)
        }
    }
}

/// 只为了读 Photon 返回的松散 properties。
enum JSONValue: Decodable {
    case string(String), number(Double), other

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .string(s) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else { self = .other }
    }

    var string: String? { if case .string(let s) = self { return s } else { return nil } }
}

/// 兼容 macOS 14–26+ 的地理编码小工具。
enum Geo {
    static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        if #available(macOS 26.0, *) {
            return item.location.coordinate
        } else {
            return legacyCoordinate(of: item)
        }
    }

    @available(macOS, deprecated: 26.0)
    private static func legacyCoordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        item.placemark.coordinate
    }

    /// 坐标所在的时区。国区 Mac 的地图数据查不到海外的时区，查不到就用最近的时区代表城市。
    static func timeZone(for coordinate: CLLocationCoordinate2D) async -> TimeZone? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        var found: TimeZone?
        if #available(macOS 26.0, *) {
            if let request = MKReverseGeocodingRequest(location: location) {
                found = try? await request.mapItems.first?.timeZone
            }
        } else {
            found = await legacyTimeZone(location)
        }
        return found ?? ZoneTable.nearest(to: coordinate)
    }

    @available(macOS, deprecated: 26.0)
    private static func legacyTimeZone(_ location: CLLocation) async -> TimeZone? {
        try? await CLGeocoder().reverseGeocodeLocation(location).first?.timeZone
    }

    /// 坐标 → 界面语言的地名（城市优先）。
    static func placeName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let zh = AppLanguage.locale
        if #available(macOS 26.0, *) {
            guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
            request.preferredLocale = zh
            guard let item = try? await request.mapItems.first else { return nil }
            return item.addressRepresentations?.cityName ?? item.name
        } else {
            return await legacyPlaceName(location, locale: zh)
        }
    }

    @available(macOS, deprecated: 26.0)
    private static func legacyPlaceName(_ location: CLLocation, locale: Locale) async -> String? {
        guard let p = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: locale).first else { return nil }
        return p.locality ?? p.administrativeArea ?? p.name ?? p.country
    }
}

/// macOS 自带的时区表（/usr/share/zoneinfo/zone.tab）：每个时区一个代表城市的坐标。
enum ZoneTable {
    private struct Zone {
        let latitude: Double
        let longitude: Double
        let identifier: String
    }

    private static let zones: [Zone] = {
        guard let text = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line -> Zone? in
            guard !line.hasPrefix("#") else { return nil }
            let columns = line.split(separator: "\t")
            guard columns.count >= 3, let (lat, lon) = parse(String(columns[1])) else { return nil }
            return Zone(latitude: lat, longitude: lon, identifier: String(columns[2]))
        }
    }()

    /// ISO 6709：±DDMM±DDDMM 或 ±DDMMSS±DDDMMSS。
    private static func parse(_ text: String) -> (Double, Double)? {
        let chars = Array(text)
        guard let split = chars.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
        func degrees(_ part: ArraySlice<Character>, degreeDigits: Int) -> Double? {
            guard let sign = part.first, part.count >= 1 + degreeDigits + 2 else { return nil }
            let digits = part.dropFirst()
            let d = Double(String(digits.prefix(degreeDigits))) ?? .nan
            let m = Double(String(digits.dropFirst(degreeDigits).prefix(2))) ?? .nan
            let s = digits.count > degreeDigits + 2 ? Double(String(digits.dropFirst(degreeDigits + 2).prefix(2))) ?? 0 : 0
            let value = d + m / 60 + s / 3600
            guard value.isFinite else { return nil }
            return sign == "-" ? -value : value
        }
        guard let lat = degrees(chars[..<split], degreeDigits: 2),
              let lon = degrees(chars[split...], degreeDigits: 3) else { return nil }
        return (lat, lon)
    }

    static func nearest(to coordinate: CLLocationCoordinate2D) -> TimeZone? {
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let zone = zones.min {
            here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                < here.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
        }
        return zone.flatMap { TimeZone(identifier: $0.identifier) }
    }
}
