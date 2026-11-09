import SwiftUI

struct PanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.page {
            case .main: MainPage()
            case .cities: CityEditorView()
            case .settings: SettingsView()
            }
        }
        .frame(width: 340)
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
            FollowExitSection()
            CitiesSection()

            HStack(spacing: 8) {
                Button {
                    MapWindow.show(model: model)
                } label: {
                    Label("打开地图", systemImage: "map")
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
        .padding(14)
    }
}

private struct DeviceHeader: View {
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
                    Text(model.status.device?.subtitle ?? "等待连接")
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
        }
    }
}

private struct DevicePicker: View {
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

private struct CurrentLocationCard: View {
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
            } else {
                Label("正在使用真实定位", systemImage: "location")
                    .font(.callout.weight(.medium))
                Text("还没改过，或已经恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("重新启动 \(model.status.device?.kind ?? "iPhone") 后会恢复真实定位。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .card()
    }
}

private struct FollowExitSection: View {
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
                    Text(model.busy ?? "跟随代理出口")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.canOperate)

            HStack(spacing: 4) {
                Group {
                    if let e = model.exit {
                        Text("出口 \(e.ip) · \(e.summary)")
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

private struct CitiesSection: View {
    @EnvironmentObject private var model: AppModel
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionTitle(title: "常用城市")
                Spacer()
                Button("编辑") { model.page = .cities }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            if model.cities.isEmpty {
                Text("还没有常用城市，点「编辑」添加。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(model.cities) { city in
                            CityButton(city: city)
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 156)
                .fixedSize(horizontal: false, vertical: model.cities.count <= 15)
            }
        }
    }
}

private struct CityButton: View {
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
                model.page = .settings
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            Spacer()
            if model.hotKeyEnabled {
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
