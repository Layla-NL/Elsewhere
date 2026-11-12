import AppKit
import SwiftUI

/// 开场页：第一次打开时盖在主窗口上（和主窗口一样大），照 Nebulium 欢迎页做。
/// 字符场一直在动，按下荡开波纹、拖动留下一串；H 的光慢慢呼吸；点「开始使用」（或回车），
/// 从按钮处开一个洞，洞口一圈快波纹，把下面的主界面露出来。
/// 开发/截图用：`-showSplash YES` 每次都显示，`-splashAppearance dark|light` 指定外观。
@MainActor
enum Splash {
    private static let shownKey = "splashShown"

    static func showIfNeeded() {
        let forced = UserDefaults.standard.bool(forKey: "showSplash")
        guard forced || !UserDefaults.standard.bool(forKey: shownKey) else { return }
        UserDefaults.standard.set(true, forKey: shownKey)
        MainWindow.show(model: AppModel.shared, splash: true)
    }
}

struct SplashOverlay: View {
    var onFinish: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var field = CodeFieldModel()
    @State private var markIn = false
    @State private var arrived = false
    @State private var leaving = false
    @State private var faded = false
    @State private var holePoint: CGPoint?
    @State private var holeRadius = 0.0
    @State private var opened = Date()
    /// 洞口扩张速度（点/毫秒）和边缘的柔化宽度，和设计稿一致。
    private static let holeSpeed = 0.85, holeEdge = 70.0

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let dark = scheme == .dark
            let markWidth = min(580, size.width * 0.56)
            let markHeight = markWidth / WordmarkGlyphs.aspectRatio
            let center = CGPoint(x: size.width / 2, y: size.height * 0.42)
            let button = CGPoint(x: size.width / 2, y: size.height - 92)
            ZStack {
                (dark ? Color(red: 5 / 255, green: 6 / 255, blue: 7 / 255) : .white)
                CodeField(dark: dark, animated: true,
                          calm: (center, CGSize(width: markWidth / 2 + 90, height: markHeight / 2 + 80)),
                          calmBottom: 170, fps: 30, model: field)
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { t in
                    Wordmark(dark: dark, glow: breathe(t.date))
                }
                .frame(width: Wordmark.size(width: markWidth).width, height: Wordmark.size(width: markWidth).height)
                .position(center)
                .opacity(markIn ? 1 : 0)
                .allowsHitTesting(false)
                .accessibilityLabel("Elsewhere")
                StartButton(dark: dark) { start(from: button, size: size) }
                    .position(button)
                    .opacity(arrived && !leaving ? 1 : 0)
                    .offset(y: leaving ? 16 : (arrived ? 0 : 14))
                    .disabled(leaving)
            }
            .mask { HoleMask(point: holePoint ?? .zero, radius: holePoint == nil ? 0 : holeRadius, edge: Self.holeEdge) }
            .opacity(faded ? 0 : 1)
            .onAppear { arrive(center: center) }
        }
        .ignoresSafeArea()
    }

    /// 进场：字标淡入，半秒后从字标中心荡一圈，1.3 秒后按钮升上来。
    private func arrive(center: CGPoint) {
        opened = Date()
        withAnimation(.easeOut(duration: reduceMotion ? 0.2 : 0.8)) { markIn = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { field.tap(at: center, strength: 0.8) }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.2 : 1.3)) {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.65)) { arrived = true }
        }
        // 截图用：`-splashDemo YES` 2.5 秒后在左上点一下、再从左下往右拖一段，和真实点击走同一条路
        if UserDefaults.standard.bool(forKey: "splashDemo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                field.drag(to: CGPoint(x: 230, y: 170)); field.endDrag()
            }
            for k in 0...8 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.7 + Double(k) * 0.1) {
                    field.drag(to: CGPoint(x: 140 + Double(k) * 32, y: 470 - Double(k) * 9))
                    if k == 8 { field.endDrag() }
                }
            }
        }
    }

    /// 点「开始使用」：按钮退下去，然后从按钮处揭开。
    private func start(from point: CGPoint, size: CGSize) {
        guard !leaving else { return }
        withAnimation(.easeOut(duration: 0.25)) { leaving = true }
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.3).delay(0.12)) { faded = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: onFinish)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            // 洞口扩到最远的角再多一圈柔边，就全露出来了
            let far = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: 0, y: size.height), CGPoint(x: size.width, y: size.height)]
                .map { hypot($0.x - point.x, $0.y - point.y) }.max() ?? 0
            let end = far + Self.holeEdge
            let duration = end / Self.holeSpeed / 1000
            holePoint = point
            field.reveal(at: point)
            withAnimation(.linear(duration: duration)) { holeRadius = end }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05, execute: onFinish)
        }
    }

    /// H 的光晕呼吸：9.6 秒一个来回，在 0.5 到 1 之间。
    private func breathe(_ date: Date) -> Double {
        guard !reduceMotion else { return 1 }
        let t = date.timeIntervalSince(opened)
        return 0.75 + 0.25 * cos(t * 2 * .pi / 9.6)
    }
}

/// 开场页的遮罩：平时整块不透明；揭幕时挖一个往外扩的圆洞，洞口边缘 edge 点软过渡。
/// 半径由 withAnimation 逐帧插值（Animatable），不用在遮罩里放 TimelineView。
private struct HoleMask: View, Animatable {
    var point: CGPoint
    var radius: Double
    var edge: Double

    var animatableData: Double {
        get { radius }
        set { radius = newValue }
    }

    var body: some View {
        if radius <= 0 {
            Rectangle()
        } else {
            let inner = max(0, radius - edge)
            Rectangle()
                .overlay {
                    Circle()
                        .fill(RadialGradient(stops: [.init(color: .black, location: 0),
                                                     .init(color: .black, location: inner / radius),
                                                     .init(color: .clear, location: 1)],
                                             center: .center, startRadius: 0, endRadius: radius))
                        .frame(width: radius * 2, height: radius * 2)
                        .position(point)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
        }
    }
}

/// 「开始使用」：主色胶囊，按下微缩。回车也能按。
private struct StartButton: View {
    var dark: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("开始使用")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 220, height: 46)
        }
        .buttonStyle(Style(dark: dark))
        .keyboardShortcut(.defaultAction)
    }

    private struct Style: ButtonStyle {
        var dark: Bool
        func makeBody(configuration: Configuration) -> some View {
            let accent = dark ? Color(.sRGB, red: 0x8E / 255, green: 0xC2 / 255, blue: 0xFE / 255)
                              : Color(.sRGB, red: 0x31 / 255, green: 0x83 / 255, blue: 0xD8 / 255)
            configuration.label
                .foregroundStyle(dark ? Color(red: 5 / 255, green: 6 / 255, blue: 7 / 255) : .white)
                .background(Capsule().fill(accent))
                .overlay(Capsule().strokeBorder(.white.opacity(dark ? 0.25 : 0.35), lineWidth: 0.5))
                .shadow(color: accent.opacity(dark ? 0.3 : 0.32), radius: dark ? 14 : 9, y: dark ? 4 : 6)
                .brightness(configuration.isPressed ? -0.06 : 0)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.25), value: configuration.isPressed)
                .contentShape(Capsule())
        }
    }
}

// MARK: 字标

/// ELSEWHERE 字标：Jost Light 大写，和 Nebulium 字标同一款字体、同样的字距。
/// 整个 H 发光上色：左竖短、右竖长（向上、向下各长出一截），两根竖都两端淡出，横杠不变。H 是「HERE」的开头。
struct Wordmark: View {
    var dark: Bool
    /// 光晕强度（开场页里呼吸用），1 是原样。
    var glow: Double = 1
    /// 留给辉光的边距。
    static let padding: CGFloat = 40

    static func size(width: CGFloat) -> CGSize {
        CGSize(width: width + padding * 2, height: width / WordmarkGlyphs.aspectRatio + padding * 2)
    }

    var body: some View {
        Canvas { ctx, size in
            let pad = Self.padding
            let box = CGRect(x: pad, y: pad, width: size.width - pad * 2, height: size.height - pad * 2)
            let ink = dark ? Color(.sRGB, red: 232 / 255, green: 237 / 255, blue: 240 / 255)
                           : Color(.sRGB, red: 17 / 255, green: 17 / 255, blue: 19 / 255)
            ctx.fill(WordmarkGlyphs.path(WordmarkGlyphs.ink, in: box), with: .color(ink))
            drawH(in: &ctx, box: box)
        }
    }

    /// 颜色和登录页字标里那一笔一致：浅色是主色 #3183D8；深色是白色，带两层蓝色光晕。
    private func drawH(in ctx: inout GraphicsContext, box: CGRect) {
        let left = WordmarkGlyphs.place(WordmarkGlyphs.leftStem, in: box)
        let right = WordmarkGlyphs.place(WordmarkGlyphs.rightStem, in: box)
        let bar = WordmarkGlyphs.place(WordmarkGlyphs.crossbar, in: box)
        let blue = Color(.sRGB, red: 0x31 / 255, green: 0x83 / 255, blue: 0xD8 / 255)
        let core = dark ? Color.white : blue
        let halos: [(radius: CGFloat, color: Color)] = dark
            ? [(12, Color(.sRGB, red: 132 / 255, green: 190 / 255, blue: 230 / 255).opacity(0.6)),
               (4, Color(.sRGB, red: 194 / 255, green: 222 / 255, blue: 242 / 255).opacity(0.9))]
            : [(10, blue.opacity(0.28)), (2.5, blue.opacity(0.3))]
        func paint(_ layer: inout GraphicsContext, _ color: Color) {
            Self.fillBeam(&layer, rect: left, color: color)
            Self.fillBeam(&layer, rect: right, color: color)
            layer.fill(Path(bar), with: .color(color))
        }
        for halo in halos {
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: halo.radius))
                layer.opacity = glow
                paint(&layer, halo.color)
            }
        }
        paint(&ctx, core)
    }

    private static func fillBeam(_ ctx: inout GraphicsContext, rect: CGRect, color: Color) {
        let end = rect.height * 0.18
        let top = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: end)
        let bottom = CGRect(x: rect.minX, y: rect.maxY - end, width: rect.width, height: end)
        let middle = CGRect(x: rect.minX, y: top.maxY, width: rect.width, height: bottom.minY - top.maxY)
        ctx.fill(Path(middle), with: .color(color))
        ctx.fill(Path(top), with: .linearGradient(Gradient(colors: [color.opacity(0), color]),
                                                  startPoint: CGPoint(x: top.midX, y: top.minY),
                                                  endPoint: CGPoint(x: top.midX, y: top.maxY)))
        ctx.fill(Path(bottom), with: .linearGradient(Gradient(colors: [color, color.opacity(0)]),
                                                     startPoint: CGPoint(x: bottom.midX, y: bottom.minY),
                                                     endPoint: CGPoint(x: bottom.midX, y: bottom.maxY)))
    }
}
