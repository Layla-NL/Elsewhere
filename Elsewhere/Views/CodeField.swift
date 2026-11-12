import AppKit
import CoreText
import SwiftUI

/// Nebulium 登录页的字符场，移植自设计稿：等宽字符铺满，疏密像一片云。
/// 会动时：云慢慢飘，字符不停地换；按下荡开一圈波纹，按住拖动一路留下小波纹。不会动时就是第一帧。
/// 系统开了「减弱动态效果」时只显示静止的一帧；窗口不在前台时暂停。
struct CodeField: View {
    var dark: Bool
    var animated = false
    /// 这块区域里的字符压暗（让文字可读），比如字标后面。
    var calm: (center: CGPoint, radius: CGSize)? = nil
    /// 内容栏：这个宽度的居中一栏里字符压淡，两边保持原来的浓度。
    var calmColumn: CGFloat? = nil
    /// 底部这么高的一条压淡（按钮后面）。
    var calmBottom: CGFloat? = nil
    /// 整体浓淡，1 是设计稿的浓度。
    var strength: Double = 1
    /// 平时的帧率；有波纹时至少 30 帧，波纹散了再降回来。
    var fps: Double = 12
    /// 外面要主动放波纹（开场页自动荡一圈、揭幕）时传进来；不传就用自己的。
    var model: CodeFieldModel? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 窗口不在前台时停下来，不占 CPU。
    @Environment(\.controlActiveState) private var activeState
    @State private var own = CodeFieldModel()
    /// 截图用：`-alwaysAnimate YES` 窗口不在前台也接着动。
    private static let alwaysAnimate = UserDefaults.standard.bool(forKey: "alwaysAnimate")
    private var field: CodeFieldModel { model ?? own }

    var body: some View {
        let field = field
        if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / (field.excited ? max(fps, 30) : fps),
                                    paused: activeState == .inactive && !Self.alwaysAnimate)) { timeline in
                canvas(field, at: timeline.date)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { field.drag(to: $0.location) }
                .onEnded { _ in field.endDrag() })
        } else {
            canvas(field, at: nil)
        }
    }

    private func canvas(_ field: CodeFieldModel, at date: Date?) -> some View {
        Canvas { ctx, size in
            field.draw(in: &ctx, size: size, now: date, dark: dark, calm: calm, column: calmColumn,
                       bottom: calmBottom, strength: strength)
        }
    }
}

/// 字符、种子和波纹放在一个引用类型里，逐帧修改不触发 SwiftUI 重新布局；只有「有没有波纹」会让帧率变。
/// 字形用 CoreText 直接画（比逐个排版 Text 快得多），菜单栏面板开着时 CPU 占用低。
@Observable @MainActor
final class CodeFieldModel {
    /// 有波纹在荡：帧率提上去，波纹才顺。
    private(set) var excited = false
    static let cell = CGSize(width: 7, height: 12)
    static let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ0123456789")
    private static let font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium) as CTFont
    private static let glyphs: [CGGlyph] = {
        var chars = charset.map { $0.utf16.first! }
        var out = [CGGlyph](repeating: 0, count: chars.count)
        CTFontGetGlyphsForCharacters(font, &chars, &out, chars.count)
        return out
    }()

    private static let levels = 32
    @ObservationIgnored private var cols = 0
    @ObservationIgnored private var rows = 0
    @ObservationIgnored private var chars: [UInt8] = []
    @ObservationIgnored private var seeds: [Double] = []
    @ObservationIgnored private var start: Date?
    @ObservationIgnored private var ripples: [Ripple] = []
    @ObservationIgnored private var rippleIndex = 0
    @ObservationIgnored private var dark = false
    @ObservationIgnored private var lastDrag: Date?

    /// 和设计稿一样：s 是强度，speed 是扩散速度（点/毫秒），width 是环宽，life 是衰减时间（毫秒）。
    struct Ripple {
        var point: CGPoint
        var time: Date
        var color: (Double, Double, Double)
        var s = 1.0, speed = 0.26, width = 34.0, life = 1500.0
    }

    /// 设计稿里的波纹颜色：浅色晨雾，深色蝶翼。
    private static func palette(dark: Bool) -> [(Double, Double, Double)] {
        dark ? [(46, 87, 219), (26, 194, 224), (158, 189, 255), (120, 160, 255)]
             : [(49, 131, 216), (66, 122, 214), (42, 163, 217), (95, 168, 238)]
    }

    private static func randomChar() -> UInt8 { UInt8.random(in: 0..<UInt8(charset.count)) }

    /// 在这里荡开一圈波纹。
    func tap(at point: CGPoint, strength: Double = 1) {
        let p = Self.palette(dark: dark)
        add(Ripple(point: point, time: Date(), color: p[rippleIndex % p.count], s: strength))
        rippleIndex += 1
    }

    /// 揭幕时洞口边上那一圈：更快、更宽、散得更快。
    func reveal(at point: CGPoint) {
        add(Ripple(point: point, time: Date(), color: Self.palette(dark: dark)[0], s: 1.1, speed: 0.85, width: 40, life: 900))
    }

    /// 按下荡一圈，按住拖动每 90 毫秒留一圈小的。
    func drag(to point: CGPoint) {
        let now = Date()
        if let last = lastDrag {
            guard now.timeIntervalSince(last) >= 0.09 else { return }
            tap(at: point, strength: 0.6)
        } else {
            tap(at: point)
        }
        lastDrag = now
    }

    func endDrag() { lastDrag = nil }

    private func add(_ ripple: Ripple) {
        ripples.append(ripple)
        if ripples.count > 14 { ripples.removeFirst() }
        if !excited { excited = true }
    }

    private func prepare(_ size: CGSize) {
        let c = Int((size.width / Self.cell.width).rounded(.up)), r = Int((size.height / Self.cell.height).rounded(.up))
        guard c != cols || r != rows else { return }
        cols = c; rows = r
        let n = c * r
        // 和设计稿同一个种子，静止的第一帧和设计稿一致
        var rng = Mulberry32(seed: 20261018)
        chars = (0..<n).map { _ in UInt8(Int(rng.next() * Double(Self.charset.count))) }
        seeds = (0..<n).map { _ in rng.next() }
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize, now: Date?, dark: Bool,
              calm: (center: CGPoint, radius: CGSize)?, column: CGFloat?, bottom: CGFloat?, strength: Double) {
        self.dark = dark
        prepare(size)
        let n = chars.count
        guard n > 0 else { return }
        let base = dark ? (232.0, 237.0, 240.0) : (70.0, 80.0, 98.0)

        var tt = 0.0
        // 每个波纹已经过去的毫秒数，逐格计算时不再重复取时间
        var live: [(ripple: Ripple, dt: Double)] = []
        if let now {
            if start == nil { start = now }
            tt = now.timeIntervalSince(start!)
            // 每帧换掉 1.2% 的字符
            for _ in 0..<max(1, n * 12 / 1000) { chars[Int.random(in: 0..<n)] = Self.randomChar() }
            ripples.removeAll { now.timeIntervalSince($0.time) > 3.2 }
            if ripples.isEmpty && excited {
                // 画的时候不能改被观察的值，放到下一轮
                DispatchQueue.main.async { [weak self] in
                    if let self, self.ripples.isEmpty { self.excited = false }
                }
            }
            live = ripples.map { ($0, now.timeIntervalSince($0.time) * 1000) }
        }

        let cols = cols, rows = rows, seeds = seeds
        let ascent = CTFontGetAscent(Self.font)
        var batchGlyphs = [[CGGlyph]](repeating: [], count: Self.levels)
        var batchPositions = [[CGPoint]](repeating: [], count: Self.levels)
        ctx.withCGContext { cg in
            // Canvas 的坐标是 y 向下，字形要翻过来画；文字矩阵也会作用在位置上，所以 y 取负
            cg.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            for r in 0..<rows {
                let y = Double(r) * Self.cell.height
                for c in 0..<cols {
                    let i = r * cols + c
                    let x = Double(c) * Self.cell.width
                    let cx = x + 3, cy = y + 6
                    // 飘动的云：哪里字符浓，哪里稀
                    let noise = 0.5 + 0.25 * sin(x * 0.021 + tt * 0.12) * cos(y * 0.017 - tt * 0.09)
                        + 0.25 * sin((x + y) * 0.011 + tt * 0.07 + seeds[i] * 0.6)
                    let quiet = calmFactor(cx, cy, calm) * columnFactor(cx, width: size.width, column: column)
                        * bottomFactor(cy, height: size.height, bottom: bottom)
                    let a = (0.012 + 0.2 * min(1, max(0, (noise - 0.56) / 0.26))) * quiet

                    var amp = 0.0
                    var tint: (Double, Double, Double)?
                    for (p, dt) in live {
                        let d = hypot(cx - p.point.x, cy - p.point.y)
                        let ring = exp(-pow((d - dt * p.speed) / p.width, 2))
                        let core = 0.55 * exp(-(d * d) / (2 * 38 * 38)) * exp(-dt / 350)
                        let v = (ring + core) * exp(-dt / p.life) * p.s
                        if v > amp { amp = v; tint = p.color }
                    }
                    if !live.isEmpty {
                        amp *= 0.2 + 0.8 * quiet
                        if amp > 0.35, Double.random(in: 0..<1) < 0.25 { chars[i] = Self.randomChar() }
                    }

                    let alpha = min(0.92, a + amp * 0.85) * strength
                    guard alpha >= 0.02 else { continue }
                    let position = CGPoint(x: x, y: -(y + ascent))
                    let glyph = Self.glyphs[Int(chars[i])]
                    if let col = tint, amp > 0.02 {
                        let m = min(1, amp * 2.2)
                        cg.setFillColor(red: (base.0 + (col.0 - base.0) * m) / 255,
                                        green: (base.1 + (col.1 - base.1) * m) / 255,
                                        blue: (base.2 + (col.2 - base.2) * m) / 255, alpha: alpha)
                        var g = glyph, pos = position
                        CTFontDrawGlyphs(Self.font, &g, &pos, 1, cg)
                    } else {
                        // 透明度分成 32 档，同一档的字一次画完
                        let level = min(Self.levels - 1, Int(alpha / 0.92 * Double(Self.levels)))
                        batchGlyphs[level].append(glyph)
                        batchPositions[level].append(position)
                    }
                }
            }
            for level in 0..<Self.levels where !batchGlyphs[level].isEmpty {
                let alpha = (Double(level) + 0.5) / Double(Self.levels) * 0.92
                cg.setFillColor(red: base.0 / 255, green: base.1 / 255, blue: base.2 / 255, alpha: alpha)
                CTFontDrawGlyphs(Self.font, batchGlyphs[level], batchPositions[level], batchGlyphs[level].count, cg)
            }
        }
    }

    /// 内容栏里压到 0.18，栏边 48 点内渐变回 1。
    private func columnFactor(_ x: Double, width: Double, column: CGFloat?) -> Double {
        guard let column else { return 1 }
        let edge = abs(x - width / 2) - Double(column) / 2
        return 0.18 + 0.82 * min(1, max(0, (edge + 24) / 48))
    }

    /// 底部一条：从 bottom 高度处往下 50 点渐变压到 0.25。
    private func bottomFactor(_ y: Double, height: Double, bottom: CGFloat?) -> Double {
        guard let bottom else { return 1 }
        return 1 - 0.75 * min(1, max(0, (y - (height - Double(bottom))) / 50))
    }

    private func calmFactor(_ x: Double, _ y: Double, _ calm: (center: CGPoint, radius: CGSize)?) -> Double {
        guard let calm else { return 1 }
        let dx = (x - calm.center.x) / calm.radius.width, dy = (y - calm.center.y) / calm.radius.height
        return min(1, max(0.08, (dx * dx + dy * dy - 0.55) / 0.6))
    }
}

/// 和设计稿同一个随机数（mulberry32）。
private struct Mulberry32 {
    var state: UInt32
    init(seed: UInt32) { state = seed }

    mutating func next() -> Double {
        state &+= 0x6D2B_79F5
        var t = (state ^ (state >> 15)) &* (1 | state)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296
    }
}
