import AppKit
import SwiftUI

@main
struct ElsewhereApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(model)
        } label: {
            Image(systemName: model.applied == nil ? "location" : "location.fill")
                .task { PanelWindow.showIfRequested(model: model) }
        }
        .menuBarExtraStyle(.window)
    }
}

/// 开发/截图用：`open Elsewhere.app --args -showPanelWindow YES` 会把面板放在一个普通窗口里。
@MainActor
enum PanelWindow {
    private static var window: NSWindow?

    static func showIfRequested(model: AppModel) {
        guard window == nil, UserDefaults.standard.bool(forKey: "showPanelWindow") else { return }
        switch UserDefaults.standard.string(forKey: "panelPage") {
        case "cities": model.page = .cities
        case "map": MapWindow.show(model: model)
        case "settings": model.page = .settings
        default: break
        }
        let hosting = NSHostingController(rootView: PanelView().environmentObject(model))
        let w = NSWindow(contentViewController: hosting)
        w.title = "Elsewhere"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}
