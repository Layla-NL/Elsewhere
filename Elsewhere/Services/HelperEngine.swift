import CryptoKit
import Foundation

/// 内置引擎：App 自带的 `elsewhere-helper`（基于开源的 idevice），不需要 Xcode。
/// 通过 macOS 自带的 usbmuxd 连接设备：插数据线，或者设备开启了无线连接（访达里的
/// 「连接 Wi-Fi 时显示此 iPhone」）并和 Mac 在同一网络。
enum HelperEngine {
    /// 打包在 Contents/Helpers 里；开发时可以用 `-helperPath` 指向 cargo 编出来的文件。
    static var executable: String? {
        if let custom = UserDefaults.standard.string(forKey: "helperPath"),
           FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/elsewhere-helper").path
        return FileManager.default.isExecutableFile(atPath: bundled) ? bundled : nil
    }

    static var isAvailable: Bool { executable != nil }

    /// 小助手每次只输出一个 JSON 对象。
    struct Reply {
        let ok: Bool
        /// 出错时的类别：locked、not_paired、not_found、ddi_missing、ddi_mount、no_service……
        let code: String?
        let error: String?
        let json: [String: Any]
    }

    private static func run(_ arguments: [String], timeout: TimeInterval) async -> Reply {
        guard let executable else {
            return Reply(ok: false, code: "missing", error: "找不到内置组件", json: [:])
        }
        let result = await Shell.run(executable, arguments, timeout: timeout)
        let line = result.stdout.split(separator: "\n").last.map(String.init) ?? ""
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return Reply(ok: false, code: "failed", error: result.output, json: [:])
        }
        return Reply(ok: json["ok"] as? Bool ?? false,
                     code: json["code"] as? String,
                     error: json["error"] as? String,
                     json: json)
    }

    // MARK: 设备

    static func listPhones() async throws -> [PhoneDevice] {
        let reply = await run(["list"], timeout: 30)
        guard reply.ok else { throw DeviceService.ListError.failed(reply.error ?? "读取设备失败") }
        let devices = reply.json["devices"] as? [[String: Any]] ?? []
        return devices.compactMap { d in
            guard let udid = d["udid"] as? String else { return nil }
            let deviceClass = d["deviceClass"] as? String ?? "iPhone"
            guard deviceClass == "iPhone" || deviceClass == "iPad" else { return nil }
            return PhoneDevice(id: udid,
                               name: d["name"] as? String ?? deviceClass,
                               model: deviceClass,
                               osVersion: d["osVersion"] as? String ?? "",
                               platform: "iOS",
                               paired: d["paired"] as? Bool ?? false,
                               developerMode: d["developerMode"] as? Bool,
                               stateText: "connected",
                               tunnelConnected: true,
                               engine: .builtIn,
                               connection: d["connection"] as? String,
                               wirelessEnabled: d["wifi"] as? Bool,
                               timeZone: d["timeZone"] as? String,
                               cellular: d["cellular"] as? Bool)
        }
    }

    // MARK: 定位

    /// 设备上还没有开发者组件时，先下载再重试一次。
    static func setLocation(device: PhoneDevice, latitude: Double, longitude: Double,
                            onDownload: @MainActor () -> Void) async -> EngineResult {
        let args = ["set", device.id, format(latitude), format(longitude), "--ddi", DeveloperDiskImage.directory.path]
        // 旧版本下载过一套不配套的文件，留着会一直挂载失败
        await Task.detached { DeveloperDiskImage.discardIfInvalid() }.value
        var reply = await run(args, timeout: 120)
        if !reply.ok, reply.code == "ddi_missing" {
            await onDownload()
            do {
                try await DeveloperDiskImage.prepare()
            } catch {
                return EngineResult(ok: false, title: "无法下载开发者组件", detail: error.localizedDescription)
            }
            reply = await run(args, timeout: 120)
        }
        return result(of: reply, device: device, action: "修改定位")
    }

    /// 开启或关闭无线连接，和访达里的「连接 Wi-Fi 时显示此 iPhone」是同一个开关。
    static func setWireless(device: PhoneDevice, enabled: Bool) async -> EngineResult {
        result(of: await run(["wifi", device.id, enabled ? "on" : "off"], timeout: 30),
               device: device, action: "更改无线连接")
    }

    static func clearLocation(device: PhoneDevice) async -> EngineResult {
        result(of: await run(["clear", device.id], timeout: 60), device: device, action: "恢复定位")
    }

    private static func result(of reply: Reply, device: PhoneDevice, action: String) -> EngineResult {
        guard !reply.ok else { return EngineResult(ok: true, title: "", detail: nil) }
        let kind = device.kind
        let title: String
        switch reply.code {
        case "locked": title = "请先解锁 \(kind)"
        case "not_paired": title = "请在 \(kind) 上信任这台 Mac"
        case "not_found": title = "\(kind) 未连接"
        case "ddi_missing": title = "缺少开发者组件"
        case "ddi_mount": title = "无法准备开发者组件，请保持 \(kind) 解锁，用数据线连接后再试"
        case "no_service": title = "\(kind) 暂时无法\(action)"
        default: title = "无法\(action)"
        }
        return EngineResult(ok: false, title: title, detail: reply.error, code: reply.code)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

/// 改定位、恢复定位的结果，两种引擎统一用它。
struct EngineResult {
    let ok: Bool
    /// 失败时给用户看的一句话。
    let title: String
    /// 原始报错，可展开查看。
    let detail: String?
    var code: String? = nil
}

/// 开发者组件，也就是 iOS 的开发者磁盘映像（个性化版本）。设备上没有时才需要，第一次用到时准备好并缓存。
/// Mac 上装过 Xcode 或系统自带了 iOS 开发者组件时直接用本机的，否则从镜像下载 Apple 官方映像。
/// 设备只会挂载 Apple 签过名的映像，签名是挂载时向 Apple 在线申请的。
enum DeveloperDiskImage {
    static let files = ["BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"]
    /// pymobiledevice3 用的同一个镜像，跟着 Xcode 更新。
    static let mirror = URL(string: "https://raw.githubusercontent.com/doronz88/DeveloperDiskImage/main/PersonalizedImages/Xcode_iOS_DDI_Personalized/")!
    /// Xcode / CoreDevice 放在本机的 iOS 开发者组件。
    static let localRestore = URL(fileURLWithPath: "/Library/Developer/DeveloperDiskImages/iOS_DDI/Restore", isDirectory: true)

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Elsewhere/DeveloperDiskImage", isDirectory: true)
    }

    enum Problem: LocalizedError {
        case mismatch
        var errorDescription: String? { "下载到的开发者组件和清单不配套（Image.dmg 的摘要不在 BuildManifest.plist 里）" }
    }

    /// 三个文件齐全，且 Image.dmg 正是清单里某个设备要的个性化映像。
    static func isValid(_ dir: URL) -> Bool {
        let fm = FileManager.default
        guard files.allSatisfy({ fm.fileExists(atPath: dir.appendingPathComponent($0).path) }),
              let manifest = try? Data(contentsOf: dir.appendingPathComponent("BuildManifest.plist")),
              let image = try? Data(contentsOf: dir.appendingPathComponent("Image.dmg"), options: .mappedIfSafe)
        else { return false }
        return personalizedDigests(manifest).contains(Data(SHA384.hash(data: image)))
    }

    /// 缓存的文件不配套就删掉，下次需要时重新准备。
    static func discardIfInvalid() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path), !isValid(directory) else { return }
        try? fm.removeItem(at: directory)
    }

    /// 先放到临时目录，校验通过后再替换，避免留下半套或不配套的文件。
    static func prepare() async throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("elsewhere-ddi-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        if !copyLocal(to: staging) {
            for name in files { try? fm.removeItem(at: staging.appendingPathComponent(name)) }
            for name in files {
                var request = URLRequest(url: mirror.appendingPathComponent(name), timeoutInterval: 120)
                request.setValue("Elsewhere", forHTTPHeaderField: "User-Agent")
                let (temp, response) = try await URLSession.shared.download(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                try fm.moveItem(at: temp, to: staging.appendingPathComponent(name))
            }
            guard isValid(staging) else { throw Problem.mismatch }
        }
        try fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        try fm.moveItem(at: staging, to: directory)
    }

    /// 按本机清单找到个性化映像和它的 trust cache，复制成统一的文件名。
    private static func copyLocal(to staging: URL) -> Bool {
        let fm = FileManager.default
        let manifestURL = localRestore.appendingPathComponent("BuildManifest.plist")
        guard let data = try? Data(contentsOf: manifestURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let identities = plist["BuildIdentities"] as? [[String: Any]],
              let manifest = identities.lazy.compactMap({ $0["Manifest"] as? [String: Any] })
                  .first(where: { $0["PersonalizedDMG"] != nil }),
              let dmg = ((manifest["PersonalizedDMG"] as? [String: Any])?["Info"] as? [String: Any])?["Path"] as? String,
              let trust = ((manifest["LoadableTrustCache"] as? [String: Any])?["Info"] as? [String: Any])?["Path"] as? String
        else { return false }
        do {
            try fm.copyItem(at: manifestURL, to: staging.appendingPathComponent("BuildManifest.plist"))
            try fm.copyItem(at: localRestore.appendingPathComponent(dmg), to: staging.appendingPathComponent("Image.dmg"))
            try fm.copyItem(at: localRestore.appendingPathComponent(trust), to: staging.appendingPathComponent("Image.dmg.trustcache"))
        } catch { return false }
        return isValid(staging)
    }

    /// 清单里所有个性化映像的 SHA-384 摘要。
    private static func personalizedDigests(_ manifest: Data) -> Set<Data> {
        guard let plist = try? PropertyListSerialization.propertyList(from: manifest, format: nil) as? [String: Any],
              let identities = plist["BuildIdentities"] as? [[String: Any]]
        else { return [] }
        return Set(identities.compactMap {
            (($0["Manifest"] as? [String: Any])?["PersonalizedDMG"] as? [String: Any])?["Digest"] as? Data
        })
    }
}
