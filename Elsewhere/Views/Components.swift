import AppKit
import SwiftUI

/// 浅色卡片背景，深浅色模式下都自然。
struct CardBackground: ViewModifier {
    var padding: CGFloat = 12
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

extension View {
    func card(padding: CGFloat = 12) -> some View { modifier(CardBackground(padding: padding)) }
}

/// 子页面顶部：返回 + 标题。
struct PageHeader: View {
    @EnvironmentObject private var model: AppModel
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Button {
                model.page = .main
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .keyboardShortcut(.cancelAction)

            Text(title).font(.headline)
            Spacer()
        }
    }
}

struct SectionTitle: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct StatusBadge: View {
    let status: DeviceStatus

    private var color: Color {
        switch status {
        case .ready: return .green
        case .checking: return .secondary
        case .notTrusted, .developerModeOff: return .orange
        case .noDevice, .unreachable: return .secondary
        case .toolsMissing, .listFailed: return .red
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(status.badge).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

/// 操作结果。失败时默认展开 devicectl 的原始输出，方便排查。
struct FeedbackView: View {
    @EnvironmentObject private var model: AppModel
    let feedback: Feedback
    @State private var expanded = true

    private var icon: String {
        switch feedback.kind {
        case .success: return "checkmark.circle.fill"
        case .failure: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch feedback.kind {
        case .success: return .green
        case .failure: return .red
        case .info: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: icon).foregroundStyle(tint)
                Text(feedback.title).font(.callout.weight(.medium))
                Spacer(minLength: 4)
                Button {
                    model.feedback = nil
                } label: {
                    Image(systemName: "xmark").font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
            if let detail = feedback.detail, !detail.isEmpty {
                if feedback.kind == .failure {
                    DisclosureGroup(isExpanded: $expanded) {
                        VStack(alignment: .trailing, spacing: 4) {
                            ScrollView {
                                Text(detail)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 110)
                            Button("拷贝") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(detail, forType: .string)
                            }
                            .buttonStyle(.link)
                            .font(.caption)
                        }
                        .padding(.top, 2)
                    } label: {
                        Text("原始输出").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(detail)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .card(padding: 10)
        .id(feedback.id)
    }
}

enum Fmt {
    static let zh = Locale(identifier: "zh_Hans")

    static func time(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "今天 " + date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(zh))
        }
        return date.formatted(.dateTime.month().day().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(zh))
    }

    static func relative(_ date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return "刚刚" }
        return date.formatted(Date.RelativeFormatStyle(presentation: .named, unitsStyle: .wide, locale: zh))
    }
}
