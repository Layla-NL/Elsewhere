import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            switch model.page {
            case .main: MainPage()
            case .cities: CityEditorView()
            case .settings: SettingsView()
            }
        }
        .frame(width: 360)
        // 底下是 Nebulium 登录页那层会动的字符场，点空白处会荡开波纹。完整功能在主窗口里，这里只放快捷操作。
        .background { CodeField(dark: scheme == .dark, animated: true, strength: 0.45) }
        .onAppear { model.panelDidOpen() }
        .onDisappear { model.panelDidClose() }
    }
}

// MARK: - 主页面

private struct MainPage: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeviceHeader()
            CurrentLocationCard()
            if model.exitFeatures { FollowExitSection() }
            CitiesSection()

            HStack(spacing: 8) {
                Button {
                    MainWindow.show(model: model)
                } label: {
                    Label("打开 Elsewhere", systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    Task { await model.clearLocation() }
                } label: {
                    Label("恢复真实定位", systemImage: "location.slash")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.canOperate)
            }
            .controlSize(.large)

            if let feedback = model.feedback {
                FeedbackView(feedback: feedback)
            }

            Divider()
            FooterBar()
        }
        .padding(16)
    }
}

struct DeviceHeader: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "iphone")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.status.device?.name ?? "iPhone")
                        .font(.headline)
                        .lineLimit(1)
                    Text(model.status.device?.subtitle ?? String(localized: "等待连接"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if model.phones.count > 1 {
                    DevicePicker()
                }
                StatusBadge(status: model.status)
            }
            if let hint = model.status.hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let wirelessHint = model.wirelessHint, !model.status.isReady {
                Text(wirelessHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.canEnableWireless {
                Button {
                    Task { await model.enableWireless() }
                } label: {
                    Label("允许无线连接", systemImage: "wifi")
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(model.busy != nil)
                .help("开启后，在同一 Wi-Fi 下拔线也能使用")
            }
        }
    }
}

struct DevicePicker: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Menu {
            Button("自动选择") { model.selectedPhoneID = nil }
            Divider()
            ForEach(model.phones) { phone in
                Button {
                    model.selectedPhoneID = phone.id
                } label: {
                    if model.status.device?.id == phone.id {
                        Label(phone.name, systemImage: "checkmark")
                    } else {
                        Text(phone.name)
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.up.chevron.down")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("切换设备")
    }
}

struct CurrentLocationCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let a = model.applied {
                HStack {
                    Label("定位已修改", systemImage: "location.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(a.source.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }
                Text(a.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                Text("\(Place.format(a.latitude, a.longitude)) · \(Fmt.time(a.date))（\(Fmt.relative(a.date))）")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let hint = model.timeZoneHint {
                    Label(hint, systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                Text(model.autoRestore
                     ? String(localized: "\(model.status.device?.kind ?? "iPhone") 重新启动后，再次连接时会自动改回。")
                     : String(localized: "重新启动 \(model.status.device?.kind ?? "iPhone") 后会恢复真实定位。"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            } else {
                Label("正在使用真实定位", systemImage: "location")
                    .font(.callout.weight(.medium))
                Text("还没改过，或已经恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }
}

struct FollowExitSection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Task { await model.followExit() }
            } label: {
                HStack(spacing: 6) {
                    if model.busy != nil {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "network")
                    }
                    Text(model.busy ?? String(localized: "跟随代理出口"))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canOperate)

            HStack(spacing: 4) {
                Group {
                    if let e = model.exit {
                        Text(verbatim: "\(model.exitFromPhone ? String(localized: "手机出口") : String(localized: "出口")) \(e.ip) · \(e.summary)")
                    } else if model.exitError != nil {
                        Text("出口 IP 查询失败")
                    } else {
                        Text("正在查询出口 IP…")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.exitError ?? model.exit?.org ?? "")
                Spacer(minLength: 4)
                Button {
                    Task { await model.refreshExit() }
                } label: {
                    if model.exitLoading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("刷新出口 IP")
            }

            if let change = model.pendingExitChange {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.swap").foregroundStyle(.secondary)
                    Text("出口变成了 \(change.summary)")
                        .font(.caption)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button("改过去") {
                        Task { await model.followExit(prefetched: change) }
                    }
                    .controlSize(.small)
                    .disabled(!model.canOperate)
                    Button {
                        model.pendingExitChange = nil
                    } label: {
                        Image(systemName: "xmark").font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
                .card(padding: 8)
            }
        }
    }
}

struct CitiesSection: View {
    @EnvironmentObject private var model: AppModel
    var columnCount = 3
    /// 菜单栏面板里点「编辑」打开主窗口的常用城市；主窗口里直接切过去。
    var onEdit: (() -> Void)? = nil
    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 6), count: columnCount) }

    init(columns: Int = 3, onEdit: (() -> Void)? = nil) {
        columnCount = columns
        self.onEdit = onEdit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle(title: "常用城市")
                Spacer()
                Button("编辑") {
                    if let onEdit { onEdit() } else { MainWindow.show(model: model, section: .cities) }
                }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            if model.cities.isEmpty {
                Text("还没有常用城市，点「编辑」添加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let grid = LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(model.cities) { city in
                        CityButton(city: city)
                    }
                }
                if onEdit != nil {
                    // 主窗口：全部摊开
                    grid
                } else {
                    // 菜单栏面板：最多露出三行，多的滚动
                    let rows = (model.cities.count + columnCount - 1) / columnCount
                    ScrollView { grid }
                        .scrollIndicators(.never)
                        .frame(height: CGFloat(min(rows, 3)) * 30 - 6)
                }
            }
        }
    }
}

struct CityButton: View {
    @EnvironmentObject private var model: AppModel
    let city: Place

    private var isCurrent: Bool {
        guard let a = model.applied else { return false }
        return city.isSameSpot(latitude: a.latitude, longitude: a.longitude)
    }

    var body: some View {
        Button {
            Task { await model.apply(place: city, source: .city) }
        } label: {
            Text(city.name)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .fontWeight(isCurrent ? .semibold : .regular)
        }
        .buttonStyle(.bordered)
        .tint(isCurrent ? .accentColor : nil)
        .disabled(!model.canOperate)
        .help(city.coordinateText)
    }
}

private struct FooterBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack {
            Button {
                MainWindow.show(model: model, section: .settings)
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            Spacer()
            if model.hotKeyEnabled && model.exitFeatures {
                Text("\(HotKey.displayString) 跟随出口")
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button("退出") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
