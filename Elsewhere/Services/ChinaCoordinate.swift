import CoreLocation
import Foundation

/// 中国大陆的地图（Apple 地图在大陆用高德底图）使用 GCJ-02「火星坐标」，
/// 而 devicectl 需要 WGS-84。地图点选 / 搜索得到的大陆坐标要先转换，否则会偏几百米。
/// 港澳台和海外不做处理。
enum ChinaCoordinate {
    private static let a = 6378245.0
    private static let ee = 0.00669342162296594323

    static func isInMainland(_ c: CLLocationCoordinate2D) -> Bool {
        let lat = c.latitude, lon = c.longitude
        guard lon > 72.004, lon < 137.8347, lat > 0.8293, lat < 55.8271 else { return false }
        let hongKong = lat > 22.13 && lat < 22.58 && lon > 113.82 && lon < 114.45
        let macau = lat > 22.10 && lat < 22.22 && lon > 113.52 && lon < 113.61
        let taiwan = lat > 21.8 && lat < 25.4 && lon > 119.3 && lon < 122.1
        return !(hongKong || macau || taiwan)
    }

    /// 地图坐标（大陆为 GCJ-02）→ 真实 GPS 坐标（WGS-84）。
    static func mapToGPS(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        isInMainland(c) ? gcjToWgs(c) : c
    }

    /// 真实 GPS 坐标 → 地图坐标，用于在地图上显示。
    static func gpsToMap(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        isInMainland(c) ? wgsToGcj(c) : c
    }

    static func wgsToGcj(_ c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        var dLat = transformLat(c.longitude - 105, c.latitude - 35)
        var dLon = transformLon(c.longitude - 105, c.latitude - 35)
        let radLat = c.latitude / 180 * .pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = dLat * 180 / ((a * (1 - ee)) / (magic * sqrtMagic) * .pi)
        dLon = dLon * 180 / (a / sqrtMagic * cos(radLat) * .pi)
        return CLLocationCoordinate2D(latitude: c.latitude + dLat, longitude: c.longitude + dLon)
    }

    /// 迭代反解，误差在厘米级。
    static func gcjToWgs(_ gcj: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        var wgs = gcj
        for _ in 0..<6 {
            let g = wgsToGcj(wgs)
            wgs.latitude -= g.latitude - gcj.latitude
            wgs.longitude -= g.longitude - gcj.longitude
        }
        return wgs
    }

    private static func transformLat(_ x: Double, _ y: Double) -> Double {
        var r = -100 + 2 * x + 3 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        r += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        r += (20 * sin(y * .pi) + 40 * sin(y / 3 * .pi)) * 2 / 3
        r += (160 * sin(y / 12 * .pi) + 320 * sin(y * .pi / 30)) * 2 / 3
        return r
    }

    private static func transformLon(_ x: Double, _ y: Double) -> Double {
        var r = 300 + x + 2 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        r += (20 * sin(6 * x * .pi) + 20 * sin(2 * x * .pi)) * 2 / 3
        r += (20 * sin(x * .pi) + 40 * sin(x / 3 * .pi)) * 2 / 3
        r += (150 * sin(x / 12 * .pi) + 300 * sin(x / 30 * .pi)) * 2 / 3
        return r
    }
}
