import AppIntents
import Foundation

// 快捷指令里的 Elsewhere 动作。都在 App 里运行：App 没开时，快捷指令会先在后台打开它。

/// 动作失败时，把面板上的那句提示交给快捷指令。
struct ElsewhereIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

@MainActor
private enum IntentRunner {
    /// 刚被快捷指令打开时还没读过设备，先读一次。
    static func prepare() async -> AppModel {
        let model = AppModel.shared
        if !model.status.isReady { await model.refreshDevices() }
        return model
    }

    /// 动作做完后，面板上的提示就是结果。
    static func outcome(_ model: AppModel) throws -> String {
        guard let feedback = model.feedback else { return String(localized: "完成") }
        if feedback.kind == .failure {
            throw ElsewhereIntentError(message: [feedback.title, feedback.detail].compactMap { $0 }.joined(separator: "："))
        }
        return feedback.title
    }
}

struct FollowExitIntent: AppIntent {
    static let title: LocalizedStringResource = "跟随代理出口"
    static let description = IntentDescription("查询代理出口 IP 的位置，把 iPhone 的定位改过去。")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await IntentRunner.prepare()
        model.feedback = nil
        await model.followExit()
        let text = try IntentRunner.outcome(model)
        return .result(value: text, dialog: "\(text)")
    }
}

struct SetCityIntent: AppIntent {
    static let title: LocalizedStringResource = "改到常用城市"
    static let description = IntentDescription("把 iPhone 的定位改到一个常用城市。")

    @Parameter(title: "城市")
    var city: CityEntity

    static var parameterSummary: some ParameterSummary {
        Summary("把定位改到 \(\.$city)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await IntentRunner.prepare()
        guard let place = model.cities.first(where: { $0.id == city.id }) else {
            throw ElsewhereIntentError(message: String(localized: "常用城市里没有「\(city.name)」"))
        }
        model.feedback = nil
        await model.apply(place: place, source: .city)
        let text = try IntentRunner.outcome(model)
        return .result(value: text, dialog: "\(text)")
    }
}

struct SetCoordinateIntent: AppIntent {
    static let title: LocalizedStringResource = "改到坐标"
    static let description = IntentDescription("把 iPhone 的定位改到指定的 GPS 坐标（WGS-84）。")

    @Parameter(title: "纬度", inclusiveRange: (-90, 90))
    var latitude: Double

    @Parameter(title: "经度", inclusiveRange: (-180, 180))
    var longitude: Double

    @Parameter(title: "名称")
    var name: String?

    static var parameterSummary: some ParameterSummary {
        Summary("把定位改到 \(\.$latitude), \(\.$longitude)") {
            \.$name
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await IntentRunner.prepare()
        let title = name?.trimmingCharacters(in: .whitespaces)
        let place = Place(name: (title?.isEmpty == false ? title! : Place.format(latitude, longitude)),
                          latitude: latitude, longitude: longitude)
        model.feedback = nil
        await model.apply(place: place, source: .custom)
        let text = try IntentRunner.outcome(model)
        return .result(value: text, dialog: "\(text)")
    }
}

struct RestoreRealLocationIntent: AppIntent {
    static let title: LocalizedStringResource = "恢复真实定位"
    static let description = IntentDescription("停止模拟，让 iPhone 恢复真实定位。")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let model = await IntentRunner.prepare()
        model.feedback = nil
        await model.clearLocation()
        let text = try IntentRunner.outcome(model)
        return .result(value: text, dialog: "\(text)")
    }
}

// MARK: 常用城市

struct CityEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "常用城市"
    static let defaultQuery = CityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(_ place: Place) {
        id = place.id
        name = place.name
    }
}

struct CityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [CityEntity] {
        await MainActor.run {
            AppModel.shared.cities.filter { identifiers.contains($0.id) }.map(CityEntity.init)
        }
    }

    func suggestedEntities() async throws -> [CityEntity] {
        await MainActor.run { AppModel.shared.cities.map(CityEntity.init) }
    }
}

// MARK: 现成的快捷指令

struct ElsewhereShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FollowExitIntent(),
                    phrases: ["用 \(.applicationName) 跟随代理出口", "\(.applicationName) 跟随出口"],
                    shortTitle: "跟随代理出口",
                    systemImageName: "network")
        AppShortcut(intent: SetCityIntent(),
                    phrases: ["用 \(.applicationName) 改到 \(\.$city)", "\(.applicationName) 改到常用城市"],
                    shortTitle: "改到常用城市",
                    systemImageName: "building.2")
        AppShortcut(intent: RestoreRealLocationIntent(),
                    phrases: ["用 \(.applicationName) 恢复真实定位"],
                    shortTitle: "恢复真实定位",
                    systemImageName: "location.slash")
    }
}
