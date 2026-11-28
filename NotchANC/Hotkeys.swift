// Keyboard shortcuts that open the card's clipboard or shelf from anywhere. Carbon's hot keys are the system's
// own mechanism for a shortcut that works in every app, and need no permission.

import AppKit
import Carbon.HIToolbox

struct Shortcut: Equatable {
    static let parts: [CardPart] = [.clipboard, .shelf]
    static let defaults: [CardPart: Shortcut] = [
        .clipboard: Shortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥V"),
        .shelf: Shortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: UInt32(controlKey | optionKey), label: "⌃⌥F"),
    ]

    var keyCode: UInt32
    var modifiers: UInt32   // Carbon's: controlKey, optionKey, shiftKey, cmdKey
    var label: String       // as shown, e.g. "⌃⌥V"

    static func key(for part: CardPart) -> String { part == .shelf ? "shortcutShelf" : "shortcutClipboard" }

    // Stored as "keyCode,modifiers,label"; an empty string means no shortcut.
    var stored: String { "\(keyCode),\(modifiers),\(label)" }

    init(keyCode: UInt32, modifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
    }

    init?(stored: String) {
        let fields = stored.split(separator: ",", maxSplits: 2).map(String.init)
        guard fields.count == 3, let keyCode = UInt32(fields[0]), let modifiers = UInt32(fields[1]), !fields[2].isEmpty else { return nil }
        self.init(keyCode: keyCode, modifiers: modifiers, label: fields[2])
    }

    // From a key press in Settings. It must hold ⌃, ⌥ or ⌘, so ordinary typing can never be taken over.
    init?(event: NSEvent) {
        let flags = event.modifierFlags
        guard !flags.isDisjoint(with: [.control, .option, .command]) else { return nil }
        let held: [(NSEvent.ModifierFlags, Int, String)] = [(.control, controlKey, "⌃"), (.option, optionKey, "⌥"),
                                                             (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")]
        let named = [kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_LeftArrow: "←", kVK_RightArrow: "→",
                     kVK_DownArrow: "↓", kVK_UpArrow: "↑"]
        guard let key = named[Int(event.keyCode)] ?? event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty else { return nil }
        self.init(keyCode: UInt32(event.keyCode),
                  modifiers: UInt32(held.filter { flags.contains($0.0) }.reduce(0) { $0 | $1.1 }),
                  label: held.filter { flags.contains($0.0) }.map(\.2).joined() + key)
    }
}

final class Hotkeys {
    private static let signature: OSType = 0x4E41_4E43   // 'NANC'
    private static let ids: [CardPart: UInt32] = [.shelf: 1, .clipboard: 2]

    var onPress: ((CardPart) -> Void)?
    private var registered: [CardPart: (shortcut: Shortcut, ref: EventHotKeyRef)] = [:]

    init() {
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            if let context, let part = Hotkeys.ids.first(where: { $0.value == id.id })?.key {
                Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue().onPress?(part)
            }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    // Idempotent: called on every settings change.
    func set(_ shortcut: Shortcut?, for part: CardPart) {
        guard shortcut != registered[part]?.shortcut, let id = Self.ids[part] else { return }
        if let old = registered.removeValue(forKey: part) { UnregisterEventHotKey(old.ref) }
        guard let shortcut else { return }
        var ref: EventHotKeyRef?
        RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: Self.signature, id: id),
                            GetApplicationEventTarget(), 0, &ref)
        if let ref { registered[part] = (shortcut, ref) }   // a combination another app holds is refused: no shortcut then
    }
}
