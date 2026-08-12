// HotKeyModifiers.swift
// VocaMac
//
// Canonical modifier representation for hotkey combos (e.g. ⌘Space, ⌃Space).
// Uses its own bit assignments rather than CGEventFlags/NSEvent.ModifierFlags
// raw values directly, so it isn't coupled to either framework's bit layout.

import Foundation

struct HotKeyModifiers: OptionSet, Hashable, Codable {
    let rawValue: Int

    static let control  = HotKeyModifiers(rawValue: 1 << 0)
    static let option   = HotKeyModifiers(rawValue: 1 << 1)
    static let shift    = HotKeyModifiers(rawValue: 1 << 2)
    static let command  = HotKeyModifiers(rawValue: 1 << 3)
    static let function = HotKeyModifiers(rawValue: 1 << 4)
}

/// A hotkey trigger: an optional set of required modifiers plus a base key.
/// When `modifiers` is empty, `keyCode` behaves exactly as the legacy
/// single-key hotkey (a lone modifier key or a lone regular key).
struct HotKeyCombo: Hashable {
    var keyCode: Int
    var modifiers: HotKeyModifiers
}
