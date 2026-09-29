import AppKit
import Carbon.HIToolbox

/// A recorded keyboard shortcut (key code + modifier flags).
public struct KeyCombo: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifierFlags: UInt  // Raw value of NSEvent.ModifierFlags

    public var isEmpty: Bool { keyCode == 0 && modifierFlags == 0 }

    public var nsModifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }

    public static let empty = KeyCombo(keyCode: 0, modifierFlags: 0)

    public init(keyCode: UInt16, modifierFlags: UInt) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }

    /// Check if an NSEvent matches this shortcut
    public func matches(_ event: NSEvent) -> Bool {
        guard !isEmpty else { return false }
        let mask: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        return event.keyCode == keyCode &&
               event.modifierFlags.intersection(mask) == nsModifierFlags.intersection(mask)
    }

    /// Checks if a chord is commonly owned by frontmost applications (e.g. ⌘1..9, ⌘T, ⌃Tab).
    public static func shadowingWarning(for combo: KeyCombo) -> String? {
        guard !combo.isEmpty else { return nil }
        let flags = combo.nsModifierFlags.intersection([.command, .control, .option, .shift])

        // ⌘1 through ⌘9 (tab switching in Safari, Chrome, Terminal)
        let numberKeyCodes: Set<UInt16> = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        if flags == .command && numberKeyCodes.contains(combo.keyCode) {
            return "This shortcut is commonly used for tab switching in browsers, Terminal, and Finder."
        }

        // ⌃Tab or ⌃⇧Tab (tab cycling in apps)
        if combo.keyCode == UInt16(kVK_Tab) && (flags == [.control] || flags == [.control, .shift]) {
            return "This shortcut is commonly used for tab cycling in applications."
        }

        // Standard editing & window keys (⌘W, ⌘Q, ⌘T, ⌘N, ⌘Z, ⌘C, ⌘V, ⌘A)
        let commonEditingKeyCodes: Set<UInt16> = [
            UInt16(kVK_ANSI_W), UInt16(kVK_ANSI_Q), UInt16(kVK_ANSI_T),
            UInt16(kVK_ANSI_N), UInt16(kVK_ANSI_Z), UInt16(kVK_ANSI_C),
            UInt16(kVK_ANSI_V), UInt16(kVK_ANSI_A)
        ]
        if flags == .command && commonEditingKeyCodes.contains(combo.keyCode) {
            return "This shortcut is a standard macOS system or application shortcut."
        }

        return nil
    }

    /// Human-readable string (e.g. "⌃⌥⌘1")
    public var displayString: String {
        if isEmpty { return "None" }
        var parts: [String] = []
        let flags = nsModifierFlags
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }
}

/// Convert a virtual key code to a display string.
private func keyCodeToString(_ keyCode: UInt16) -> String {
    let specialKeys: [UInt16: String] = [
        UInt16(kVK_Return): "↩",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_ANSI_0): "0",
        UInt16(kVK_ANSI_1): "1",
        UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4",
        UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6",
        UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9",
    ]
    if let str = specialKeys[keyCode] { return str }

    // Fallback via TISCopyCurrentKeyboardInputSource
    if let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
       let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
        let dataRef = unsafeBitCast(layoutData, to: CFData.self)
        let keyLayout = unsafeBitCast(CFDataGetBytePtr(dataRef), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = UCKeyTranslate(
            keyLayout,
            keyCode,
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            4,
            &length,
            &chars
        )
        if status == noErr && length > 0 {
            return String(utf16CodeUnits: chars, count: length).uppercased()
        }
    }

    return "?"
}
