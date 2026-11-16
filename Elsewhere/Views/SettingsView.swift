import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    private var version: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PageHeader(title: "设置")

            VStack(alignment: .leading, spacing: 10) {
                SettingRow(title: "代理出口功能",
                           detail: "跟随代理出口、出口变化提醒和快捷键。关掉后不再查询出口 IP，界面上也不显示，只用来改定位。",
                           isOn: $model.exitFeatures)
            }
            .toggleStyle(.switch)
            .card()

            if model.exitFeatures {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "代理出口变化时")
                Picker("代理出口变化时", selection: $model.watchMode) {
                    ForEach(ExitWatchMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                Text("每 30 秒检查一次出口 IP，在 Surge 等工具里切换节点就会被发现。「自动改」只在当前定位来自「跟随代理出口」时生效，不会覆盖你手动选的城市。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
            }

            VStack(alignment: .leading, spacing: 10) {
                SettingRow(title: "开机自动启动", detail: nil,
                           isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
                if model.launchAtLoginNeedsApproval {
                    HStack(spacing: 4) {
                        Text("需要在系统设置里允许。").font(.caption).foregroundStyle(.secondary)
                        Button("打开登录项设置") { model.openLoginItemsSettings() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                Divider()
                SettingRow(title: "同时修改所有设备",
                           detail: "连着多台 iPhone 或 iPad 时，一次全部修改。",
                           isOn: $model.applyToAll)
                Divider()
                SettingRow(title: "重新连接后恢复定位",
                           detail: "设备重新启动后，再次连接时自动改回上次的位置。",
                           isOn: $model.autoRestore)
                if model.exitFeatures {
                    Divider()
                    SettingRow(title: "全局快捷键 \(HotKey.displayString)",
                               detail: "随时按下就跟随代理出口改定位，结果用系统通知告诉你。",
                               isOn: $model.hotKeyEnabled)
                }
            }
            .toggleStyle(.switch)
            .card()

            if model.exitFeatures {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "出口来源")
                Picker("出口来源", selection: $model.exitFromPhone) {
                    Text("本机").tag(false)
                    Text("手机").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                if model.exitFromPhone {
                    TextField("手机代理地址，如 192.168.1.20:1082", text: $model.phoneProxy)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Text(model.phoneProxyInvalid
                         ? String(localized: "请填写「IP 地址:端口」。")
                         : String(localized: "在手机的代理 App 中开启代理共享，填写它显示的地址和端口。手机和 Mac 需在同一 Wi-Fi。"))
                        .font(.caption)
                        .foregroundStyle(model.phoneProxyInvalid ? .orange : .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("按这台 Mac 的网络查询出口。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .card()
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "定位方式")
                Picker("定位方式", selection: $model.engineMode) {
                    ForEach(EngineMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 3) {
                    EngineLine(name: String(localized: "内置"), available: HelperEngine.isAvailable, detail: String(localized: "无需 Xcode"))
                    EngineLine(name: "Xcode", available: model.toolsPath != nil,
                               detail: model.toolsPath == nil ? String(localized: "未安装") : String(localized: "已安装"))
                }
            }
            .card()

            Text("Elsewhere \(version)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .onAppear { model.refreshLaunchAtLogin() }
    }
}

private struct EngineLine: View {
    let name: String
    let available: Bool
    let detail: String

    var body: some View {
        Label {
            Text("\(name)：\(detail)")
        } icon: {
            Image(systemName: available ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(available ? .green : .secondary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

private struct SettingRow: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}
