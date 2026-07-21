import Carbon
import Foundation

final class HotkeyManager: @unchecked Sendable {
    static let shared = HotkeyManager()
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), Self.handleEvent, 1, &event, nil, &handler)
    }

    func register(key: String) {
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = nil
        guard let keyCode = Self.keyCode(for: key) else { return }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x4E415449), id: 1) // NATI
        guard RegisterEventHotKey(keyCode, UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &ref) == noErr else { return }
        hotkey = ref
    }

    private static let handleEvent: EventHandlerUPP = { _, _, _ in
        NotificationCenter.default.post(name: .showTranslator, object: nil)
        return noErr
    }

    private static func keyCode(for key: String) -> UInt32? {
        let codes: [Character: UInt32] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
            "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16,
            "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
            "n": 45, "m": 46
        ]
        return key.lowercased().first.flatMap { codes[$0] }
    }
}

extension Notification.Name {
    static let showTranslator = Notification.Name("showTranslator")
    static let hotkeyChanged = Notification.Name("hotkeyChanged")
}
