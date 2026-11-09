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
                SettingRow(title: "重新连接后恢复定位",
                           detail: "设备重新启动后，再次连接时自动改回上次的位置。",
                           isOn: $model.autoRestore)
                Divider()
                SettingRow(title: "全局快捷键 \(HotKey.displayString)",
                           detail: "随时按下就跟随代理出口改定位，结果用系统通知告诉你。",
                           isOn: $model.hotKeyEnabled)
            }
            .toggleStyle(.switch)
            .card()

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
                    EngineLine(name: "内置", available: HelperEngine.isAvailable, detail: "无需 Xcode")
                    EngineLine(name: "Xcode", available: model.toolsPath != nil,
                               detail: model.toolsPath == nil ? "未安装" : "已安装")
                }
            }
            .card()

            Text("Elsewhere \(version)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
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
    let title: String
    let detail: String?
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
