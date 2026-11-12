import SwiftUI

struct CityEditorView: View {
    @EnvironmentObject private var model: AppModel
    @State private var name = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var error: String?
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PageHeader(title: "编辑常用城市")

            List {
                ForEach(model.cities) { city in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(.tertiary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(city.name)
                            Text(city.coordinateText)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            model.removeCity(city)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("删除")
                    }
                    .padding(.vertical, 1)
                }
                .onMove { model.moveCities(from: $0, to: $1) }
            }
            .listStyle(.inset)
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.08)))

            Text("拖动可以排序。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "添加城市")
                TextField("名称，例如 首尔", text: $name)
                HStack {
                    TextField("纬度", text: $latitude)
                    TextField("经度", text: $longitude)
                }
                .monospacedDigit()
                Text("可以直接粘贴「37.5665, 126.9780」到纬度框。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button("在地图上选…") { MapWindow.show(model: model) }
                    Spacer()
                    Button("添加") { add() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || latitude.isEmpty)
                }
            }
            .textFieldStyle(.roundedBorder)
            .card()

            HStack {
                Spacer()
                Button("恢复默认城市") { confirmReset = true }
                    .buttonStyle(.link)
                    .font(.caption)
                    .confirmationDialog("把常用城市恢复成默认的 11 个？", isPresented: $confirmReset) {
                        Button("恢复默认", role: .destructive) { model.resetCities() }
                    } message: {
                        Text("你自己添加的城市会被删除。")
                    }
            }
        }
        .padding(18)
    }

    private func add() {
        var latText = latitude
        var lonText = longitude
        // 支持把「纬度, 经度」一次贴进纬度框。
        let pasted = latitude.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " }).map(String.init).filter { !$0.isEmpty }
        if pasted.count == 2 {
            latText = pasted[0]
            lonText = pasted[1]
        }
        guard let lat = Double(latText.trimmingCharacters(in: .whitespaces)), (-90...90).contains(lat) else {
            error = "纬度要在 -90 到 90 之间。"
            return
        }
        guard let lon = Double(lonText.trimmingCharacters(in: .whitespaces)), (-180...180).contains(lon) else {
            error = "经度要在 -180 到 180 之间。"
            return
        }
        model.addCity(Place(name: name.trimmingCharacters(in: .whitespaces), latitude: lat, longitude: lon))
        name = ""
        latitude = ""
        longitude = ""
        error = nil
    }
}
