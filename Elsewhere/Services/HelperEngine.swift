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
                               engine: .builtIn)
        }
    }

    // MARK: 定位

    /// 设备上还没有开发者组件时，先下载再重试一次。
    static func setLocation(device: PhoneDevice, latitude: Double, longitude: Double,
                            onDownload: @MainActor () -> Void) async -> EngineResult {
        let args = ["set", device.id, format(latitude), format(longitude), "--ddi", DeveloperDiskImage.directory.path]
        var reply = await run(args, timeout: 120)
        if !reply.ok, reply.code == "ddi_missing" {
            await onDownload()
            do {
                try await DeveloperDiskImage.download()
            } catch {
                return EngineResult(ok: false, title: "无法下载开发者组件", detail: error.localizedDescription)
            }
            reply = await run(args, timeout: 120)
        }
        return result(of: reply, device: device, action: "修改定位")
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
        case "ddi_mount": title = "无法准备开发者组件"
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

/// 开发者组件，也就是 iOS 的开发者磁盘映像。设备上没有时才需要，第一次用到时下载并缓存。
/// 文件来自 Apple 官方映像的镜像；设备只会挂载 Apple 签过名的映像，签名是挂载时向 Apple 在线申请的。
enum DeveloperDiskImage {
    static let files = ["BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"]
    static let mirror = URL(string: "https://raw.githubusercontent.com/swipt-automation/DeveloperDiskImage/main/")!

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Elsewhere/DeveloperDiskImage", isDirectory: true)
    }

    static var isDownloaded: Bool {
        files.allSatisfy { FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }
    }

    /// 先下载到临时目录，全部成功后再替换，避免留下半套文件。
    static func download() async throws {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("elsewhere-ddi-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        for name in files {
            var request = URLRequest(url: mirror.appendingPathComponent(name), timeoutInterval: 120)
            request.setValue("Elsewhere", forHTTPHeaderField: "User-Agent")
            let (temp, response) = try await URLSession.shared.download(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            try fm.moveItem(at: temp, to: staging.appendingPathComponent(name))
        }
        try fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        try fm.moveItem(at: staging, to: directory)
    }
}
