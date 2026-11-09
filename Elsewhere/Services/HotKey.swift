import Carbon
import Foundation

/// 全局快捷键 ⌃⌥⌘L。用 Carbon 的 RegisterEventHotKey，不需要辅助功能权限。
final class HotKey {
    static let shared = HotKey()
    static let displayString = "⌃⌥⌘L"

    var action: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    func register() {
        installHandlerIfNeeded()
        guard hotKeyRef == nil else { return }
        let id = EventHotKeyID(signature: OSType(0x454C_5357), id: 1) // "ELSW"
        RegisterEventHotKey(UInt32(kVK_ANSI_L),
                            UInt32(controlKey | optionKey | cmdKey),
                            id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.shared.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}
