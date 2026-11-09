import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Page { case main, cities, settings }

    /// 操作是谁发起的：面板里点的，还是快捷键 / 自动跟随（面板可能没打开，要发通知）。
    enum Origin { case panel, background }

    private enum Key {
        static let cities = "cities"
        static let applied = "appliedLocation"
        static let watchMode = "exitWatchMode"
        static let hotKey = "hotKeyEnabled"
        static let selectedPhone = "selectedPhoneID"
    }

    static let devicePollInterval: Duration = .seconds(4)
    static let exitPollInterval: Duration = .seconds(30)

    // MARK: 状态

    @Published var page: Page = .main
    @Published private(set) var status: DeviceStatus = .checking
    @Published private(set) var phones: [PhoneDevice] = []
    @Published var selectedPhoneID: String? {
        didSet {
            defaults.set(selectedPhoneID, forKey: Key.selectedPhone)
            recomputeStatus()
        }
    }

    @Published private(set) var applied: AppliedLocation? {
        didSet { save(applied, Key.applied) }
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
    @Published private(set) var toolsPath: String?

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
        refreshLaunchAtLogin()
        start()
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
        if toolsPath == nil {
            let check = await DeviceService.checkTools()
            guard check.ok else {
                status = .toolsMissing(check.output)
                return
            }
            toolsPath = check.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        do {
            phones = try await DeviceService.listPhones()
            recomputeStatus()
        } catch DeviceService.ListError.failed(let output) {
            status = .listFailed(output)
        } catch {
            status = .listFailed(error.localizedDescription)
        }
    }

    private func recomputeStatus() {
        guard toolsPath != nil else { return }
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
        report(.failure, "\(status.device?.kind ?? "iPhone") 还没准备好", detail: status.hint ?? status.badge, origin: origin)
        return nil
    }

    // MARK: 改定位

    func followExit(prefetched: ExitInfo? = nil, origin: Origin = .panel) async {
        guard busy == nil, let phone = readyPhone(origin: origin) else { return }
        let info: ExitInfo
        if let prefetched {
            info = prefetched
        } else {
            busy = "正在查询代理出口…"
            do {
                info = try await ExitIPService.lookup()
            } catch {
                busy = nil
                exitError = error.localizedDescription
                report(.failure, "查不到出口 IP 的位置", detail: error.localizedDescription, origin: origin)
                return
            }
            busy = nil
        }
        exit = info
        exitError = nil
        lastSeenIP = info.ip
        lastExitFetch = Date()
        pendingExitChange = nil
        await apply(name: "出口 · \(info.displayCity)", latitude: info.latitude, longitude: info.longitude,
                    source: .exitIP, ip: info.ip, phone: phone, origin: origin)
    }

    func apply(place: Place, source: LocationSource) async {
        guard busy == nil, let phone = readyPhone(origin: .panel) else { return }
        await apply(name: place.name, latitude: place.latitude, longitude: place.longitude,
                    source: source, ip: nil, phone: phone, origin: .panel)
    }

    private func apply(name: String, latitude: Double, longitude: Double, source: LocationSource,
                       ip: String?, phone: PhoneDevice, origin: Origin) async {
        busy = "正在修改定位…"
        let result = await DeviceService.setLocation(device: phone.id, latitude: latitude, longitude: longitude)
        busy = nil
        if result.ok {
            applied = AppliedLocation(name: name, latitude: latitude, longitude: longitude, date: Date(),
                                      source: source, ip: ip, deviceName: phone.name)
            var detail = Place.format(latitude, longitude)
            if let ip { detail += " · IP \(ip)" }
            report(.success, "已改到 \(name)", detail: detail, origin: origin)
        } else {
            report(.failure, "改定位失败", detail: result.output, origin: origin)
            await refreshDevices()
        }
    }

    func clearLocation() async {
        guard busy == nil, let phone = readyPhone(origin: .panel) else { return }
        busy = "正在恢复真实定位…"
        let result = await DeviceService.clearLocation(device: phone.id)
        busy = nil
        if result.ok {
            applied = nil
            // Wi-Fi 版 iPad 没有 GPS，要等它重新用 Wi-Fi 算出位置，这段时间会停在模拟的地方。
            let note = phone.kind == "iPad"
                ? "iPad 没有 GPS 时要靠 Wi-Fi 重新定位，可能会在原地停一会儿；一直不变的话，到「设置 › 隐私与安全性 › 定位服务」关掉再打开。"
                : nil
            report(.success, "已恢复真实定位", detail: note, origin: .panel)
        } else {
            report(.failure, "恢复失败", detail: result.output, origin: .panel)
            await refreshDevices()
        }
    }

    // MARK: 出口 IP

    func refreshExit() async {
        exitLoading = true
        defer { exitLoading = false }
        do {
            let info = try await ExitIPService.lookup()
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
        guard let ip = try? await ExitIPService.currentIP() else { return }
        guard let previous = lastSeenIP else {
            lastSeenIP = ip
            return
        }
        guard ip != previous else { return }
        lastSeenIP = ip

        guard let info = try? await ExitIPService.lookup() else { return }
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
        Notifier.shared.post(title: "代理出口变了",
                             body: "现在是 \(info.summary)（\(info.ip)）。点「改过去」把 iPhone 定位跟过去。",
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
        if hotKeyEnabled { HotKey.shared.register() } else { HotKey.shared.unregister() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            report(.failure, "设置开机启动失败", detail: error.localizedDescription, origin: .panel)
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
