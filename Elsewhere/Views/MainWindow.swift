import AppKit
import SwiftUI

/// 主窗口的各个栏目。以后加功能就在这里加一项。
enum MainSection: String, CaseIterable, Identifiable {
    case location, map, cities, device, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .location: return "定位"
        case .map: return "地图"
        case .cities: return "常用城市"
        case .device: return "设备"
        case .settings: return "设置"
        }
    }

    var symbol: String {
        switch self {
        case .location: return "location"
        case .map: return "map"
        case .cities: return "building.2"
        case .device: return "iphone"
        case .settings: return "gearshape"
        }
    }
}

/// 主窗口：左边侧边栏，右边内容，底下铺着会动的字符场。菜单栏面板只放快捷操作，完整功能都在这里。
@MainActor
enum MainWindow {
    private static var window: NSWindow?
    private static let state = MainWindowState()

    /// splash 为真时先盖上开场页（第一次打开）。
    static func show(model: AppModel, section: MainSection? = nil, splash: Bool = false) {
        if let section { state.section = section }
        if splash { state.splash = true }
        if window == nil {
            let root = MainWindowView().environmentObject(model).environmentObject(state)
            let hosting = NSHostingController(rootView: root)
            hosting.sizingOptions = []
            let w = NSWindow(contentViewController: hosting)
            w.title = "Elsewhere"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 980, height: 660))
            w.contentMinSize = NSSize(width: 820, height: 560)
            let defaults = UserDefaults.standard
            if let look = defaults.string(forKey: "panelAppearance") ?? defaults.string(forKey: "splashAppearance") {
                w.appearance = NSAppearance(named: look == "dark" ? .darkAqua : .aqua)
            }
            w.setFrameAutosaveName("ElsewhereMain")
            if w.frame.origin == .zero { w.center() }
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class MainWindowState: ObservableObject {
    @Published var section: MainSection = .location
    @Published var splash = false
}

/// 在主窗口里时，子页面不显示面板用的「返回」标题栏。
private struct InMainWindowKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var inMainWindow: Bool {
        get { self[InMainWindowKey.self] }
        set { self[InMainWindowKey.self] = newValue }
    }
}

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var state: MainWindowState
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            split
            if state.splash {
                SplashOverlay { state.splash = false }
            }
        }
    }

    private var split: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                Wordmark(dark: scheme == .dark)
                    .frame(width: Wordmark.size(width: 150).width, height: Wordmark.size(width: 150).height)
                    .padding(.leading, -Wordmark.padding + 16)
                    .padding(.top, 18)
                    .padding(.bottom, -Wordmark.padding + 14)
                    .accessibilityLabel("Elsewhere")
                List(MainSection.allCases, selection: Binding(get: { state.section }, set: { if let s = $0 { state.section = s } })) { section in
                    Label(section.title, systemImage: section.symbol).tag(section)
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
                .environment(\.inMainWindow, true)
        }
        .onAppear { model.panelDidOpen() }
    }

    @ViewBuilder private var detail: some View {
        switch state.section {
        case .map:
            MapWindowView()
        default:
            ZStack {
                CodeField(dark: scheme == .dark, animated: true, calmColumn: 720, strength: 0.7)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(state.section.title)
                            .font(.largeTitle.weight(.semibold))
                        page
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    @ViewBuilder private var page: some View {
        switch state.section {
        case .location: LocationPage()
        case .cities: CityEditorView().padding(-18)
        case .device: DevicePage()
        case .settings: SettingsView().padding(-18)
        case .map: EmptyView()
        }
    }
}

// MARK: - 定位

private struct LocationPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var state: MainWindowState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DeviceHeader().card(padding: 14)
            CurrentLocationCard()
            if model.exitFeatures { FollowExitSection() }
            CitiesSection(columns: 4, onEdit: { state.section = .cities })
            HStack(spacing: 10) {
                Button {
                    state.section = .map
                } label: {
                    Label("在地图上选", systemImage: "map").frame(maxWidth: .infinity)
                }
                Button {
                    Task { await model.clearLocation() }
                } label: {
                    Label("恢复真实定位", systemImage: "location.slash").frame(maxWidth: .infinity)
                }
                .disabled(!model.canOperate)
            }
            .controlSize(.large)
            if let feedback = model.feedback {
                FeedbackView(feedback: feedback)
            }
        }
    }
}

// MARK: - 设备

private struct DevicePage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DeviceHeader().card(padding: 14)
            if model.phones.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "已连接的设备")
                    ForEach(model.phones) { phone in
                        HStack(spacing: 10) {
                            Image(systemName: phone.kind == "iPad" ? "ipad" : "iphone")
                                .foregroundStyle(.secondary)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(phone.name)
                                Text(phone.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.status.device?.id == phone.id {
                                Text("当前").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Button("切换") { model.selectedPhoneID = phone.id }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                .card(padding: 14)
            }
            Button {
                Task { await model.refreshDevices() }
            } label: {
                Label("重新检测设备", systemImage: "arrow.clockwise")
            }
        }
    }
}
