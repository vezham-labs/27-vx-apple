import AppKit
import Carbon.HIToolbox

/// Reads shortcut characters the way macOS menus do: from the paired Latin
/// layout for non-Latin input, and from a layout's ⌘ layer when it defines one.
enum KeyLayout {
    private struct Layout {
        let data: Data
        let isLatin: Bool

        init?(_ source: TISInputSource) {
            guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
            data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
            isLatin = KeyLayout.isLatin(source)
        }

        init(data: Data, isLatin: Bool) {
            self.data = data
            self.isLatin = isLatin
        }

        func type(_ keyCode: UInt16, modifiers: Int, action: Int = kUCKeyActionDown) -> String? {
            data.withUnsafeBytes { raw -> String? in
                guard let base = raw.baseAddress else { return nil }
                let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
                var dead: UInt32 = 0
                var length = 0
                var typed = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, keyCode, UInt16(action), UInt32(modifiers >> 8) & 0xFF, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &dead, typed.count, &length, &typed
                )
                guard status == noErr, length > 0 else { return nil }
                return String(utf16CodeUnits: typed, count: length)
            }
        }

        func underCommand(_ keyCode: UInt16, shift: Bool) -> String? {
            guard let plain = type(keyCode, modifiers: 0),
                  let command = type(keyCode, modifiers: cmdKey),
                  plain.lowercased() != command.lowercased()
            else { return nil }
            return (shift ? type(keyCode, modifiers: cmdKey | shiftKey) : command)?.lowercased()
        }

    }

    static func shortcut(_ keyCode: UInt16, flags: NSEvent.ModifierFlags, shift: Bool, typed: String?) -> String {
        let fallback = typed?.lowercased() ?? ""
        guard !flags.isDisjoint(with: [.command, .control, .option]),
              let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
        else { return fallback }

        let keyboard = TISCopyCurrentKeyboardLayoutInputSource().flatMap { Layout($0.takeRetainedValue()) }
        let layout = Layout(data: keyboard?.data ?? Data(), isLatin: isLatin(current))
        if !layout.isLatin {
            return pairedLatin()?.type(keyCode, modifiers: shift ? shiftKey : 0, action: kUCKeyActionDisplay)?
                .lowercased() ?? fallback
        }
        if flags.contains(.command), let key = layout.underCommand(keyCode, shift: shift) { return key }
        return fallback
    }

    private static func pairedLatin() -> Layout? {
        TISCopyCurrentASCIICapableKeyboardLayoutInputSource().flatMap { Layout($0.takeRetainedValue()) }
    }

    private static func isLatin(_ source: TISInputSource) -> Bool {
        guard let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsASCIICapable) else { return true }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(value).takeUnretainedValue())
    }
}
