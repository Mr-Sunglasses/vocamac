// SavedCommand.swift
// VocaMac
//
// Command Mode instructions the user keeps: run with a shortcut, by name, or
// from the Shortcuts app.

import Foundation

/// An instruction saved so it doesn't have to be spoken in full each time.
///
/// It runs three ways: its own keyboard shortcut applies it to the selection
/// without recording anything, saying its name in Command Mode stands in for
/// the instruction, and the "Edit Selected Text" Shortcuts action can pass it.
struct SavedCommand: Codable, Identifiable, Equatable {
    var id: UUID
    /// What it is called, and what to say to run it ("Fix grammar").
    var name: String
    /// The instruction Command Mode is given.
    var instruction: String
    /// `HotKeyCombo.storageString`, or empty for no shortcut.
    var shortcut: String

    init(id: UUID = UUID(), name: String, instruction: String, shortcut: String = "") {
        self.id = id
        self.name = name
        self.instruction = instruction
        self.shortcut = shortcut
    }

    /// Neither a name to say nor an instruction to run.
    var isUsable: Bool {
        !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Commands offered the first time the list is opened. None has a
    /// shortcut: a global shortcut takes its keys from every app.
    static let starters: [SavedCommand] = [
        SavedCommand(name: "Fix grammar", instruction: "fix grammar and spelling"),
        SavedCommand(name: "Shorter", instruction: "make this shorter"),
        SavedCommand(name: "More formal", instruction: "make it more formal"),
    ]
}

enum SavedCommandStore {
    static func decode(_ json: String) -> [SavedCommand] {
        guard let data = json.data(using: .utf8),
              let commands = try? JSONDecoder().decode([SavedCommand].self, from: data) else { return [] }
        return commands
    }

    static func encode(_ commands: [SavedCommand]) -> String {
        guard let data = try? JSONEncoder().encode(commands),
              let json = String(data: data, encoding: .utf8) else { return "" }
        return json
    }

    /// The saved command whose name is what was said, compared the way
    /// instructions are: without case, punctuation, or "please".
    static func command(named spoken: String, in commands: [SavedCommand]) -> SavedCommand? {
        let wanted = CommandInstruction.normalized(spoken)
        guard !wanted.isEmpty else { return nil }
        return commands.first { $0.isUsable && CommandInstruction.normalized($0.name) == wanted }
    }

    /// Shortcut names, one per line or comma-separated, as typed in Settings.
    static func shortcutNames(from text: String) -> [String] {
        text.split { $0 == "\n" || $0 == "," }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
