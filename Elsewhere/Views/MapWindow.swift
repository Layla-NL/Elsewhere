import AppKit
import MapKit
import SwiftUI

/// 独立的地图窗口。菜单栏 App 没有主窗口，所以自己管一个 NSWindow。
@MainActor
enum MapWindow {
    private static var window: NSWindow?

    static func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: MapWindowView().environmentObject(model))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Elsewhere 地图"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 960, height: 640))
            w.contentMinSize = NSSize(width: 720, height: 500)
            w.setFrameAutosaveName("ElsewhereMap")
            if w.frame.origin == .zero { w.center() }
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 地图底图样式。
private enum MapLook: String, CaseIterable, Identifiable {
    case standard, hybrid, imagery
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return "标准"
        case .hybrid: return "混合"
        case .imagery: return "卫星"
        }
    }
    var style: MapStyle {
        switch self {
        case .standard: return .standard(pointsOfInterest: .all)
        case .hybrid: return .hybrid
        case .imagery: return .imagery
        }
    }
}

struct MapWindowView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var search = PlaceSearch()
    /// 先看大范围；知道 iPhone 或出口在哪之后再飞到城市级别。
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 25, longitude: 10),
        span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 160)))
    @State private var cameraPlaced = false
    /// 选中的点，地图坐标（大陆是 GCJ-02）。
    @State private var pin: CLLocationCoordinate2D?
    @State private var pinName = ""
    @State private var look: MapLook = .standard
    @State private var notFound = false
    @State private var enteringCoordinates = false
    @State private var coordinateText = ""
    @State private var note: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                if let applied = model.applied {
                    Annotation("iPhone · \(applied.name)", coordinate: map(applied.latitude, applied.longitude)) {
                        Badge(symbol: "iphone", color: .blue)
                    }
                }
                if let exit = model.exit {
                    Annotation("代理出口 · \(exit.displayCity)", coordinate: map(exit.latitude, exit.longitude)) {
                        Badge(symbol: "globe", color: .orange)
                    }
                }
                if let pin {
                    Marker(displayName, coordinate: pin).tint(.red)
                }
            }
            .mapStyle(look.style)
            .mapControls {
                MapCompass()
                MapZoomStepper()
                MapScaleView()
            }
            .onTapGesture { point in
                if let coordinate = proxy.convert(point, from: .local) {
                    select(coordinate, name: nil, moveCamera: false)
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) { searchPanel }
        .overlay(alignment: .topTrailing) { lookPicker }
        .overlay(alignment: .bottom) { controlBar }
        .frame(minWidth: 720, minHeight: 500)
        .onAppear(perform: start)
        .onChange(of: model.exit) { _, _ in placeCamera() }
        .onChange(of: model.applied) { _, applied in
            // 刚改完定位，地图跟过去，选中的点也就用完了。
            guard let applied else { return }
            pin = nil
            jump(to: map(applied.latitude, applied.longitude))
        }
    }

    // MARK: 上方：搜索

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索地名、地址或地标", text: $search.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { Task { await submitSearch() } }
                if search.searching {
                    ProgressView().controlSize(.small)
                } else if !search.query.isEmpty {
                    Button { search.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                Divider().frame(height: 16)
                Button { enteringCoordinates.toggle() } label: {
                    Image(systemName: "number")
                }
                .buttonStyle(.plain)
                .help("输入坐标")
                .popover(isPresented: $enteringCoordinates, arrowEdge: .bottom) { coordinateEntry }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

            if search.hasSuggestions {
                suggestions
            } else if notFound {
                Text("没搜到这个地方，换个关键词试试。")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(width: 360)
        .padding(.top, 36)
        .padding(.leading, 14)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(search.osmResults) { place in
                suggestionRow(title: place.name, subtitle: place.detail, symbol: "globe") {
                    select(map(place.latitude, place.longitude), name: place.name, moveCamera: true)
                }
                Divider().padding(.leading, 34)
            }
            ForEach(Array(search.results.prefix(5).enumerated()), id: \.offset) { _, item in
                suggestionRow(title: item.title, subtitle: item.subtitle, symbol: "map") {
                    Task {
                        if let (name, coordinate) = await search.resolve(item) {
                            select(coordinate, name: name, moveCamera: true)
                        }
                    }
                }
                Divider().padding(.leading, 34)
            }
            suggestionRow(title: "按回车精确搜索「\(search.query)」", subtitle: "海外地名用中文也能搜到", symbol: "return") {
                Task { await submitSearch() }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    private func suggestionRow(title: String, subtitle: String, symbol: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.callout).lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var coordinateEntry: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("输入 GPS 坐标").font(.headline)
            TextField("纬度, 经度，例如 34.0522, -118.2437", text: $coordinateText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(submitCoordinates)
            HStack {
                Text("按 GPS（WGS-84）坐标理解。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("定位到这里", action: submitCoordinates)
                    .buttonStyle(.borderedProminent)
                    .disabled(Self.parse(coordinateText) == nil)
            }
        }
        .padding(14)
    }

    private var lookPicker: some View {
        Picker("地图", selection: $look) {
            ForEach(MapLook.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .padding(.top, 36)
        .padding(.trailing, 64)
    }

    // MARK: 下方：操作栏

    private var controlBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                selectionSummary
                Spacer(minLength: 8)
                deviceState
            }
            HStack(spacing: 8) {
                Button {
                    Task {
                        await model.followExit()
                        if let exit = model.exit { jump(to: map(exit.latitude, exit.longitude)) }
                    }
                } label: {
                    Label("跟随出口", systemImage: "globe")
                }
                .disabled(!model.canOperate)

                Button {
                    guard let gps = gpsPin else { return }
                    model.addCity(Place(name: displayName, latitude: gps.latitude, longitude: gps.longitude))
                    note = "已收藏到常用城市"
                } label: {
                    Label("收藏", systemImage: "star")
                }
                .disabled(pin == nil)

                if model.applied != nil {
                    Button(role: .destructive) {
                        Task { await model.clearLocation() }
                    } label: {
                        Label("恢复真实定位", systemImage: "location.slash")
                    }
                    .disabled(!model.canOperate)
                }

                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    guard let gps = gpsPin else { return }
                    Task {
                        await model.apply(place: Place(name: displayName, latitude: gps.latitude, longitude: gps.longitude),
                                          source: .custom)
                    }
                } label: {
                    HStack(spacing: 6) {
                        if model.busy != nil { ProgressView().controlSize(.small) }
                        Text("应用到 iPhone")
                    }
                    .frame(minWidth: 110)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(pin == nil || !model.canOperate)
            }
            .controlSize(.large)

            if let feedback = model.feedback {
                FeedbackView(feedback: feedback)
            }
        }
        .padding(14)
        .frame(maxWidth: 760)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        .padding(14)
    }

    @ViewBuilder
    private var selectionSummary: some View {
        if pin != nil, let gps = gpsPin {
            VStack(alignment: .leading, spacing: 3) {
                TextField("名称", text: $pinName, prompt: Text("地图选点"))
                    .textFieldStyle(.plain)
                    .font(.headline)
                Text(Place.format(gps.latitude, gps.longitude)
                     + (ChinaCoordinate.isInMainland(pin!) ? "  （已从地图坐标转为 GPS 坐标）" : ""))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } else if let applied = model.applied {
            VStack(alignment: .leading, spacing: 3) {
                Text("iPhone 当前在 \(applied.name)").font(.headline)
                Text("\(Place.format(applied.latitude, applied.longitude)) · 在地图上点一下或搜索，选新的位置")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("iPhone 正在用真实定位").font(.headline)
                Text("在地图上点一下、搜索地名，或输入坐标，选一个位置")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var deviceState: some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone").foregroundStyle(.secondary)
            Text(model.status.device?.name ?? "iPhone")
                .font(.callout)
                .lineLimit(1)
            StatusBadge(status: model.status)
        }
        .help(model.status.hint ?? "")
    }

    // MARK: 逻辑

    private var gpsPin: CLLocationCoordinate2D? { pin.map(ChinaCoordinate.mapToGPS) }

    private var displayName: String {
        let trimmed = pinName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "地图选点" : trimmed
    }

    private func map(_ latitude: Double, _ longitude: Double) -> CLLocationCoordinate2D {
        ChinaCoordinate.gpsToMap(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
    }

    private func start() {
        searchFocused = true
        Task { await model.refreshDevices() }
        if model.exit == nil { Task { await model.refreshExit() } }
        placeCamera()
    }

    /// 只在第一次知道该看哪里时移动地图，之后不打扰用户自己拖动。
    private func placeCamera() {
        guard !cameraPlaced, pin == nil else { return }
        let target = model.applied.map { map($0.latitude, $0.longitude) }
            ?? model.exit.map { map($0.latitude, $0.longitude) }
        guard let target else { return }
        cameraPlaced = true
        position = .region(MKCoordinateRegion(center: target, latitudinalMeters: 40_000, longitudinalMeters: 40_000))
    }

    private func jump(to coordinate: CLLocationCoordinate2D) {
        withAnimation {
            position = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 30_000, longitudinalMeters: 30_000))
        }
    }

    private func submitSearch() async {
        let text = search.query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        notFound = false
        if let coordinate = Self.parse(text) {
            select(map(coordinate.latitude, coordinate.longitude), name: nil, moveCamera: true)
        } else if let place = await search.lookUpOSM(text) {
            select(map(place.latitude, place.longitude), name: place.name, moveCamera: true)
        } else if let first = search.results.first, let (name, coordinate) = await search.resolve(first) {
            select(coordinate, name: name, moveCamera: true)
        } else if let (name, coordinate) = await search.resolve(text: text) {
            select(coordinate, name: name, moveCamera: true)
        } else {
            notFound = true
        }
    }

    private func submitCoordinates() {
        guard let gps = Self.parse(coordinateText) else { return }
        enteringCoordinates = false
        select(map(gps.latitude, gps.longitude), name: nil, moveCamera: true)
    }

    private func select(_ coordinate: CLLocationCoordinate2D, name: String?, moveCamera: Bool) {
        pin = coordinate
        note = nil
        notFound = false
        search.clear()
        if moveCamera { jump(to: coordinate) }
        if let name {
            pinName = name
        } else {
            pinName = ""
            Task {
                let found = await Geo.placeName(for: coordinate)
                // 用户可能已经点了别的地方。
                guard let current = pin,
                      abs(current.latitude - coordinate.latitude) < 1e-9,
                      abs(current.longitude - coordinate.longitude) < 1e-9,
                      pinName.isEmpty else { return }
                pinName = found ?? ""
            }
        }
    }

    /// "34.05, -118.24"、"34.05，-118.24"、"34.05 -118.24" 都认。
    static func parse(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              abs(lat) <= 90, abs(lon) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// 地图上的圆形图标标注。
private struct Badge: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
    }
}
