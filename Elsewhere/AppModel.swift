import CoreLocation
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    /// 整个 App 共用一个，快捷指令也用它。
    static let shared = AppModel()

    enum Page { case main, cities, settings }

    /// 操作是谁发起的：面板里点的，还是快捷键 / 自动跟随（面板可能没打开，要发通知）。
    enum Origin { case panel, background }

    private enum Key {
        static let cities = "cities"
        static let applied = "appliedLocation"
        static let watchMode = "exitWatchMode"
        static let hotKey = "hotKeyEnabled"
        static let selectedPhone = "selectedPhoneID"
        static let engineMode = "engineMode"
        static let wirelessDevices = "wirelessDevices"
        static let autoRestore = "autoRestore"
        static let exitFromPhone = "exitFromPhone"
        static let exitFeatures = "exitFeatures"
        static let phoneProxy = "phoneProxy"
        static let applyToAll = "applyToAll"
    }

    static let devicePollInterval: Duration = .seconds(4)
    static let exitPollInterval: Duration = .seconds(30)

    #if DEBUG
    /// 截图、录屏用：`-demo YES` 换成一台假的 iPhone 和假的出口（文档用 IP），不碰真设备，也不保存任何设置。
    static let demo = UserDefaults.standard.bool(forKey: "demo")
    #else
    static let demo = false
    #endif

    // MARK: 状态

    @Published var page: Page = .main
    @Published private(set) var status: DeviceStatus = .checking
    @Published private(set) var phones: [PhoneDevice] = []
    @Published var selectedPhoneID: String? {
        didSet {
            if !Self.demo { defaults.set(selectedPhoneID, forKey: Key.selectedPhone) }
            recomputeStatus()
        }
    }

    @Published private(set) var applied: AppliedLocation? {
        didSet {
            save(applied, Key.applied)
            if applied?.latitude != oldValue?.latitude || applied?.longitude != oldValue?.longitude {
                pendingRestore = [:]
                updateAppliedTimeZone()
            }
        }
    }

    @Published var cities: [Place] {
        didSet { save(cities, Key.cities) }
    }

    /// 正在进行的操作，nil 表示空闲。
    @Published private(set) var busy: String?
    @Published var feedback: Feedback?

    @Published private(set) var exit: ExitInfo?
    @Published private(set) var exitError: String?
    @Published private(set) var exitLoading = false
    /// 检测到出口变了、但还没改过去。
    @Published var pendingExitChange: ExitInfo?

    @Published var watchMode: ExitWatchMode {
        didSet { defaults.set(watchMode.rawValue, forKey: Key.watchMode) }
    }

    @Published var hotKeyEnabled: Bool {
        didSet {
            defaults.set(hotKeyEnabled, forKey: Key.hotKey)
            applyHotKey()
        }
    }

    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchAtLoginNeedsApproval = false
    /// Xcode 的 devicectl 路径；nil 表示没装或还没检查。
    @Published private(set) var toolsPath: String?
    private var toolsChecked = false

    /// 开过无线连接的设备：UDID → 「iPhone」或「iPad」。拔线后找不到它们时给出提示。
    @Published private(set) var wirelessDevices: [String: String] = [:] {
        didSet { defaults.set(wirelessDevices, forKey: Key.wirelessDevices) }
    }

    /// 开过无线连接的设备现在一台都不在：多半是设备用了私有 Wi-Fi 地址，或不在同一网络。
    var wirelessHint: String? {
        guard !wirelessDevices.isEmpty,
              !phones.contains(where: { wirelessDevices[$0.id] != nil && $0.engine == .builtIn }) else { return nil }
        let kind = Set(wirelessDevices.values).count == 1 ? wirelessDevices.values.first! : String(localized: "各设备")
        return String(localized: "无线连接需要和 Mac 在同一 Wi-Fi，并在\(kind)的无线局域网设置中关闭「私有无线局域网地址」。")
    }

    /// 同时修改所有已连接、已就绪的设备。
    @Published var applyToAll: Bool {
        didSet { if !Self.demo { defaults.set(applyToAll, forKey: Key.applyToAll) } }
    }

    /// 出口来源：false 为本机，true 为手机（经手机代理 App 共享的代理查询）。
    /// 代理出口相关的功能（跟随出口、出口提醒、快捷键）。关掉后不再查询出口 IP，界面上也不显示，只用来改定位。
    @Published var exitFeatures: Bool {
        didSet {
            guard exitFeatures != oldValue else { return }
            if !Self.demo { defaults.set(exitFeatures, forKey: Key.exitFeatures) }
            if exitFeatures {
                Task { await refreshExit() }
            } else {
                exit = nil
                exitError = nil
                pendingExitChange = nil
            }
            applyHotKey()
        }
    }

    @Published var exitFromPhone: Bool {
        didSet {
            defaults.set(exitFromPhone, forKey: Key.exitFromPhone)
            exitSourceChanged()
        }
    }

    /// 手机代理共享的地址，例如 "192.168.1.20:1082"。
    @Published var phoneProxy: String {
        didSet {
            defaults.set(phoneProxy, forKey: Key.phoneProxy)
            if exitFromPhone { exitSourceChanged() }
        }
    }

    /// 查出口用的代理；本机为 nil。选了手机但地址填错时也为 nil，并在界面上提示。
    var exitProxy: ExitProxy? {
        exitFromPhone ? ExitProxy(phoneProxy) : nil
    }

    var phoneProxyInvalid: Bool { exitFromPhone && ExitProxy(phoneProxy) == nil }

    private func exitSourceChanged() {
        exit = nil
        exitError = nil
        lastSeenIP = nil
        lastExitFetch = nil
        guard !phoneProxyInvalid else { return }
        Task { await refreshExit() }
    }

    /// 设备重新连接（比如重启后）时，自动改回上次的位置。
    @Published var autoRestore: Bool {
        didSet { defaults.set(autoRestore, forKey: Key.autoRestore) }
    }

    /// 当前修改的位置所在的时区，用来和设备的时区比对。
    @Published private(set) var appliedTimeZone: TimeZone?

    /// 上一次刷新时在线的设备；nil 表示还没刷新过（刚启动时不算「重新连接」）。
    private var presentIDs: Set<String>?
    /// 等待恢复定位的设备 → 已经尝试的次数。
    private var pendingRestore: [String: Int] = [:]
    private static let restoreAttempts = 15

    /// 设置里的「定位方式」。
    @Published var engineMode: EngineMode {
        didSet {
            defaults.set(engineMode.rawValue, forKey: Key.engineMode)
            Task { await refreshDevices() }
        }
    }

    var canOperate: Bool { status.isReady && busy == nil }

    private let defaults = UserDefaults.standard
    private var lastSeenIP: String?
    private var lastExitFetch: Date?
    private var feedbackDismissTask: Task<Void, Never>?
    private var started = false

    // MARK: 初始化

    init() {
        cities = Self.load([Place].self, Key.cities, from: .standard) ?? Place.defaults
        applied = Self.load(AppliedLocation.self, Key.applied, from: .standard)
        watchMode = ExitWatchMode(rawValue: UserDefaults.standard.string(forKey: Key.watchMode) ?? "") ?? .notify
        hotKeyEnabled = UserDefaults.standard.object(forKey: Key.hotKey) as? Bool ?? true
        selectedPhoneID = UserDefaults.standard.string(forKey: Key.selectedPhone)
        engineMode = EngineMode(rawValue: UserDefaults.standard.string(forKey: Key.engineMode) ?? "") ?? .auto
        wirelessDevices = UserDefaults.standard.dictionary(forKey: Key.wirelessDevices) as? [String: String] ?? [:]
        autoRestore = UserDefaults.standard.object(forKey: Key.autoRestore) as? Bool ?? true
        exitFromPhone = UserDefaults.standard.bool(forKey: Key.exitFromPhone)
        exitFeatures = UserDefaults.standard.object(forKey: Key.exitFeatures) == nil ? true : UserDefaults.standard.bool(forKey: Key.exitFeatures)
        applyToAll = UserDefaults.standard.bool(forKey: Key.applyToAll)
        phoneProxy = UserDefaults.standard.string(forKey: Key.phoneProxy) ?? ""
        updateAppliedTimeZone()
        refreshLaunchAtLogin()
        if Self.demo { startDemo() } else { start() }
    }

    private func startDemo() {
        let phone = PhoneDevice(id: "demo", name: "iPhone", model: "iPhone 17 Pro", osVersion: "27.0", platform: "iOS",
                                paired: true, developerMode: true, stateText: "available (paired)", tunnelConnected: true,
                                engine: .builtIn, connection: "usb", wirelessEnabled: true)
        phones = [phone]
        status = .ready(phone)
        applied = nil
        // `-demoCities cn` 换成国内城市，录国内宣传视频用
        if UserDefaults.standard.string(forKey: "demoCities") == "cn" {
            cities = [
                Place(name: "上海", latitude: 31.2304, longitude: 121.4737),
                Place(name: "北京", latitude: 39.9042, longitude: 116.4074),
                Place(name: "成都", latitude: 30.5728, longitude: 104.0668),
                Place(name: "杭州", latitude: 30.2741, longitude: 120.1551),
                Place(name: "深圳", latitude: 22.5431, longitude: 114.0579),
                Place(name: "广州", latitude: 23.1291, longitude: 113.2644),
                Place(name: "西安", latitude: 34.3416, longitude: 108.9398),
                Place(name: "重庆", latitude: 29.5630, longitude: 106.5516),
            ]
        }
        if exitFeatures {
            exit = ExitInfo(ip: "203.0.113.24", city: "Tokyo", region: "Tokyo", country: "JP",
                            latitude: 35.6895, longitude: 139.6917)
        }
        lastExitFetch = Date()
    }

    private func start() {
        guard !started else { return }
        started = true

        Notifier.shared.setUp()
        Notifier.shared.onFollow = { [weak self] in
            Task { await self?.followExit(origin: .background) }
        }
        HotKey.shared.action = { [weak self] in
            Task { await self?.followExit(origin: .background) }
        }
        applyHotKey()

        Task { [weak self] in
            while let self {
                await self.refreshDevices()
                try? await Task.sleep(for: Self.devicePollInterval)
            }
        }

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await self?.refreshExit()
            while let self {
                try? await Task.sleep(for: Self.exitPollInterval)
                if self.watchMode != .off { await self.checkExitChange() }
            }
        }
    }

    // MARK: 设备

    func refreshDevices() async {
        guard !Self.demo else { return }
        let useBuiltIn = engineMode != .xcode && HelperEngine.isAvailable
        let useXcode = engineMode != .builtIn
        if useXcode && !toolsChecked {
            let check = await DeviceService.checkTools()
            toolsChecked = true
            toolsPath = check.ok ? check.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        }
        if engineMode == .xcode && toolsPath == nil {
            status = .toolsMissing("")
            return
        }
        if engineMode == .builtIn && !HelperEngine.isAvailable {
            status = .listFailed(String(localized: "找不到内置组件"))
            return
        }

        var found: [PhoneDevice] = []
        var failures: [String] = []
        var anySucceeded = false
        if useBuiltIn {
            do {
                found = try await HelperEngine.listPhones()
                anySucceeded = true
            } catch DeviceService.ListError.failed(let output) {
                failures.append(output)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        if useXcode && toolsPath != nil {
            do {
                for phone in try await DeviceService.listPhones() {
                    if let i = found.firstIndex(where: { $0.id == phone.id }) {
                        // 内置引擎能连上的设备仍由它负责，只借用 Xcode 给的完整型号名。
                        let b = found[i]
                        found[i] = PhoneDevice(id: b.id, name: b.name, model: phone.model, osVersion: b.osVersion,
                                               platform: b.platform, paired: b.paired, developerMode: b.developerMode,
                                               stateText: b.stateText, tunnelConnected: b.tunnelConnected, engine: .builtIn,
                                               connection: b.connection, wirelessEnabled: b.wirelessEnabled,
                                               timeZone: b.timeZone, cellular: b.cellular)
                    } else {
                        found.append(phone)
                    }
                }
                anySucceeded = true
            } catch DeviceService.ListError.failed(let output) {
                failures.append(output)
            } catch {
                failures.append(error.localizedDescription)
            }
        }
        guard anySucceeded else {
            status = .listFailed(failures.joined(separator: "\n"))
            return
        }
        phones = found
        // 只算真的连得上的：Xcode 会一直列出认识的设备，哪怕它正在重启。
        let ids = Set(found.filter { $0.engine == .builtIn || $0.tunnelConnected }.map(\.id))
        if let previous = presentIDs, autoRestore {
            for id in applied?.devices ?? [] where ids.contains(id) && !previous.contains(id) && pendingRestore[id] == nil {
                pendingRestore[id] = 0
            }
        }
        presentIDs = ids
        for phone in found where phone.engine == .builtIn {
            if phone.wirelessEnabled == true, wirelessDevices[phone.id] == nil {
                wirelessDevices[phone.id] = phone.kind
            } else if phone.wirelessEnabled == false, wirelessDevices[phone.id] != nil {
                wirelessDevices[phone.id] = nil
            }
        }
        recomputeStatus()
        await restorePending()
    }

    // MARK: 重新连接后恢复

    /// 设备重启后模拟定位会失效。重新连上时把上次的位置再设一次；刚开机还锁着屏，就过一会儿再试。
    private func restorePending() async {
        guard let a = applied else { return }
        for id in a.devices where pendingRestore[id] != nil {
            await restore(id, to: a)
        }
    }

    private func restore(_ id: String, to a: AppliedLocation) async {
        guard busy == nil, let tries = pendingRestore[id],
              let phone = phones.first(where: { $0.id == id }), isReady(phone) else { return }
        busy = String(localized: "正在恢复定位…")
        let result = await setLocation(on: phone, latitude: a.latitude, longitude: a.longitude)
        busy = nil
        if result.ok {
            pendingRestore[id] = nil
            report(.success, String(localized: "已恢复到 \(a.name)"), detail: String(localized: "\(phone.name) 重新连接后，已改回上次的位置。"), origin: .background)
        } else if tries + 1 < Self.restoreAttempts {
            pendingRestore[id] = tries + 1
        } else {
            pendingRestore[id] = nil
            report(.failure, String(localized: "无法恢复定位"), detail: result.detail ?? result.title, origin: .background)
        }
    }

    // MARK: 时区

    private func updateAppliedTimeZone() {
        guard let a = applied else {
            appliedTimeZone = nil
            return
        }
        let coordinate = CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude)
        Task { [weak self] in
            let zone = await Geo.timeZone(for: coordinate)
            guard let self, self.applied?.latitude == a.latitude, self.applied?.longitude == a.longitude else { return }
            self.appliedTimeZone = zone
        }
    }

    /// 设备的时区和当前修改的位置对不上时给出提示。改完一分钟内不提示，给系统留出自动更新的时间。
    var timeZoneHint: String? {
        guard let a = applied, let expected = appliedTimeZone, Date().timeIntervalSince(a.date) > 60,
              let (phone, current) = a.devices.lazy.compactMap({ id -> (PhoneDevice, TimeZone)? in
                  guard let phone = self.phones.first(where: { $0.id == id }),
                        let zone = phone.timeZone.flatMap(TimeZone.init(identifier:)),
                        zone.secondsFromGMT() != expected.secondsFromGMT() else { return nil }
                  return (phone, zone)
              }).first else { return nil }
        let name = current.localizedName(for: .generic, locale: AppLanguage.locale) ?? current.identifier
        // 有蜂窝网络时，自动时区以运营商为准，只能手动选。
        if phone.cellular == false {
            return String(localized: "\(phone.kind) 的时区（\(name)）与定位不一致。在「设置」>「通用」>「日期与时间」中打开「自动设定时区」。")
        }
        return String(localized: "\(phone.kind) 的时区（\(name)）与定位不一致。在「设置」>「通用」>「日期与时间」中关闭「自动设定时区」，然后选择同一时区的城市。")
    }

    private func recomputeStatus() {
        let phone: PhoneDevice?
        if let id = selectedPhoneID, let p = phones.first(where: { $0.id == id }) {
            phone = p
        } else {
            // 优先选现在连得上的 iPhone。
            phone = phones.sorted { score($0) > score($1) }.first
        }
        guard let phone else {
            status = .noDevice
            return
        }
        if !phone.paired && phone.reachable {
            status = .notTrusted(phone)
        } else if !phone.reachable {
            status = .unreachable(phone)
        } else if phone.developerMode == false {
            status = .developerModeOff(phone)
        } else {
            status = .ready(phone)
        }
    }

    private func score(_ p: PhoneDevice) -> Int {
        (p.reachable ? 4 : 0) + (p.paired ? 2 : 0) + (p.model.hasPrefix("iPhone") ? 1 : 0)
    }

    /// 没准备好就给出失败提示并返回 nil。
    private func readyPhone(origin: Origin) -> PhoneDevice? {
        if case .ready(let phone) = status { return phone }
        report(.failure, String(localized: "\(status.device?.kind ?? "iPhone") 还没准备好"), detail: status.hint ?? status.badge, origin: origin)
        return nil
    }

    private func isReady(_ phone: PhoneDevice) -> Bool {
        phone.paired && phone.reachable && phone.developerMode != false
    }

    /// 要改的设备：当前选中的那台；打开「同时修改所有设备」时，再加上其他就绪的设备。
    private func targets(origin: Origin) -> [PhoneDevice]? {
        guard let selected = readyPhone(origin: origin) else { return nil }
        guard applyToAll else { return [selected] }
        return [selected] + phones.filter { $0.id != selected.id && isReady($0) }
    }

    // MARK: 改定位

    func followExit(prefetched: ExitInfo? = nil, origin: Origin = .panel) async {
        guard busy == nil, let phones = targets(origin: origin) else { return }
        let info: ExitInfo
        if let prefetched {
            info = prefetched
        } else if Self.demo, let demoExit = exit {
            info = demoExit
        } else {
            busy = String(localized: "正在查询代理出口…")
            do {
                info = try await ExitIPService.lookup(proxy: exitProxy)
            } catch {
                busy = nil
                exitError = error.localizedDescription
                report(.failure, String(localized: "查不到出口 IP 的位置"), detail: error.localizedDescription, origin: origin)
                return
            }
            busy = nil
        }
        exit = info
        exitError = nil
        lastSeenIP = info.ip
        lastExitFetch = Date()
        pendingExitChange = nil
        await apply(name: String(localized: "出口 · \(info.displayCity)"), latitude: info.latitude, longitude: info.longitude,
                    source: .exitIP, ip: info.ip, phones: phones, origin: origin)
    }

    func apply(place: Place, source: LocationSource) async {
        guard busy == nil, let phones = targets(origin: .panel) else { return }
        await apply(name: place.name, latitude: place.latitude, longitude: place.longitude,
                    source: source, ip: nil, phones: phones, origin: .panel)
    }

    private func apply(name: String, latitude: Double, longitude: Double, source: LocationSource,
                       ip: String?, phones: [PhoneDevice], origin: Origin) async {
        busy = String(localized: "正在修改定位…")
        var done: [PhoneDevice] = []
        var failures: [(PhoneDevice, EngineResult)] = []
        for phone in phones {
            let result = await setLocation(on: phone, latitude: latitude, longitude: longitude)
            if result.ok { done.append(phone) } else { failures.append((phone, result)) }
        }
        busy = nil
        if !done.isEmpty {
            applied = AppliedLocation(name: name, latitude: latitude, longitude: longitude, date: Date(),
                                      source: source, ip: ip,
                                      deviceName: done.map(\.name).joined(separator: "、"),
                                      deviceID: done[0].id, deviceIDs: done.map(\.id))
        }
        if failures.isEmpty {
            var detail = Place.format(latitude, longitude)
            if let ip { detail += " · IP \(ip)" }
            if done.count > 1 { detail += String(localized: " · \(done.count) 台设备") }
            report(.success, String(localized: "已改到 \(name)"), detail: detail, origin: origin)
        } else {
            let (phone, result) = failures[0]
            let title = phones.count > 1 ? "\(phone.name)：\(result.title)" : result.title
            report(.failure, title, detail: result.detail, origin: origin)
            await refreshDevices()
        }
    }

    func clearLocation() async {
        guard busy == nil, var phones = targets(origin: .panel) else { return }
        // 上次一起改过、现在也连着的设备，一并恢复。
        for id in applied?.devices ?? [] where !phones.contains(where: { $0.id == id }) {
            if let p = self.phones.first(where: { $0.id == id }), isReady(p) { phones.append(p) }
        }
        busy = String(localized: "正在恢复真实定位…")
        var failures: [(PhoneDevice, EngineResult)] = []
        for phone in phones {
            let result = await clearLocation(on: phone)
            if !result.ok { failures.append((phone, result)) }
        }
        busy = nil
        if failures.isEmpty {
            applied = nil
            // Wi-Fi 版 iPad 没有 GPS，要等它重新用 Wi-Fi 算出位置，这段时间会停在模拟的地方。
            let note = phones.contains { $0.kind == "iPad" } ? String(localized: "iPad 可能需要片刻才能重新定位。") : nil
            report(.success, String(localized: "已恢复真实定位"), detail: note, origin: .panel)
        } else {
            let (phone, result) = failures[0]
            let title = phones.count > 1 ? "\(phone.name)：\(result.title)" : result.title
            report(.failure, title, detail: result.detail, origin: .panel)
            await refreshDevices()
        }
    }

    // MARK: 无线连接

    /// 插线时可以开启：之后在同一个 Wi-Fi 下拔线也能用。
    var canEnableWireless: Bool {
        guard case .ready(let phone) = status else { return false }
        return phone.engine == .builtIn && !phone.isWireless && phone.wirelessEnabled == false
    }

    func enableWireless() async {
        guard busy == nil, case .ready(let phone) = status else { return }
        busy = String(localized: "正在开启无线连接…")
        let result = await HelperEngine.setWireless(device: phone, enabled: true)
        busy = nil
        if result.ok {
            report(.success, String(localized: "已开启无线连接"), detail: String(localized: "在同一 Wi-Fi 下，拔线后仍可使用。"), origin: .panel)
        } else {
            report(.failure, result.title, detail: result.detail, origin: .panel)
        }
        await refreshDevices()
    }

    // MARK: 引擎

    /// 内置引擎失败、而 Xcode 也能连上这台设备时，自动换 Xcode 再试一次。
    private func canFallBack(_ phone: PhoneDevice, after result: EngineResult) -> Bool {
        engineMode == .auto && phone.engine == .builtIn && toolsPath != nil
            && result.code != "locked" && result.code != "not_paired"
    }

    private func setLocation(on phone: PhoneDevice, latitude: Double, longitude: Double) async -> EngineResult {
        if Self.demo {
            try? await Task.sleep(for: .milliseconds(700))
            return EngineResult(ok: true, title: "", detail: nil)
        }
        if phone.engine == .builtIn {
            let result = await HelperEngine.setLocation(device: phone, latitude: latitude, longitude: longitude) {
                self.busy = String(localized: "正在下载开发者组件…")
            }
            guard !result.ok, canFallBack(phone, after: result) else { return result }
        }
        let r = await DeviceService.setLocation(device: phone.id, latitude: latitude, longitude: longitude)
        return EngineResult(ok: r.ok, title: String(localized: "无法修改定位"), detail: r.ok ? nil : r.output)
    }

    private func clearLocation(on phone: PhoneDevice) async -> EngineResult {
        if Self.demo {
            try? await Task.sleep(for: .milliseconds(500))
            return EngineResult(ok: true, title: "", detail: nil)
        }
        if phone.engine == .builtIn {
            let result = await HelperEngine.clearLocation(device: phone)
            guard !result.ok, canFallBack(phone, after: result) else { return result }
        }
        let r = await DeviceService.clearLocation(device: phone.id)
        return EngineResult(ok: r.ok, title: String(localized: "无法恢复定位"), detail: r.ok ? nil : r.output)
    }

    // MARK: 出口 IP

    func refreshExit() async {
        guard exitFeatures else { return }
        guard !Self.demo else { return }
        guard !phoneProxyInvalid else {
            exitError = String(localized: "手机代理地址无效")
            return
        }
        exitLoading = true
        defer { exitLoading = false }
        do {
            let info = try await ExitIPService.lookup(proxy: exitProxy)
            exit = info
            exitError = nil
            lastSeenIP = info.ip
            lastExitFetch = Date()
        } catch {
            exitError = error.localizedDescription
        }
    }

    /// 面板打开时，如果出口信息有点旧了就刷新一下。
    func panelDidOpen() {
        Task { await refreshDevices() }
        if let last = lastExitFetch, Date().timeIntervalSince(last) < 60 { return }
        Task { await refreshExit() }
    }

    func panelDidClose() {
        page = .main
    }

    private func checkExitChange() async {
        guard exitFeatures else { return }
        guard !phoneProxyInvalid else { return }
        guard let ip = try? await ExitIPService.currentIP(proxy: exitProxy) else { return }
        guard let previous = lastSeenIP else {
            lastSeenIP = ip
            return
        }
        guard ip != previous else { return }
        lastSeenIP = ip

        guard let info = try? await ExitIPService.lookup(proxy: exitProxy) else { return }
        exit = info
        exitError = nil
        lastExitFetch = Date()

        guard status.isReady else { return }
        if applied?.source == .exitIP, applied?.ip == info.ip { return }

        // 自动模式只在当前定位本来就是「跟随出口」时生效，不覆盖手动选的位置。
        if watchMode == .auto, applied?.source == .exitIP {
            await followExit(prefetched: info, origin: .background)
            return
        }
        pendingExitChange = info
        Notifier.shared.post(title: String(localized: "代理出口变了"),
                             body: String(localized: "现在是 \(info.summary)（\(info.ip)）。点「改过去」把 iPhone 定位跟过去。"),
                             category: Notifier.exitChangedCategory)
    }

    // MARK: 常用城市

    func addCity(_ place: Place) {
        cities.append(place)
    }

    func removeCity(_ place: Place) {
        cities.removeAll { $0.id == place.id }
    }

    func moveCities(from source: IndexSet, to destination: Int) {
        cities.move(fromOffsets: source, toOffset: destination)
    }

    func resetCities() {
        cities = Place.defaults
    }

    // MARK: 设置

    private func applyHotKey() {
        if hotKeyEnabled && exitFeatures { HotKey.shared.register() } else { HotKey.shared.unregister() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            report(.failure, String(localized: "设置开机启动失败"), detail: error.localizedDescription, origin: .panel)
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        let s = SMAppService.mainApp.status
        launchAtLogin = s == .enabled
        launchAtLoginNeedsApproval = s == .requiresApproval
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: 反馈

    func report(_ kind: Feedback.Kind, _ title: String, detail: String?, origin: Origin) {
        feedbackDismissTask?.cancel()
        feedback = Feedback(kind: kind, title: title, detail: detail)
        if kind == .success {
            feedbackDismissTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                self?.feedback = nil
            }
        }
        if origin == .background {
            Notifier.shared.post(title: title, body: detail ?? "")
        }
    }

    // MARK: 存取

    private func save<T: Encodable>(_ value: T?, _ key: String) {
        guard !Self.demo else { return }
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
