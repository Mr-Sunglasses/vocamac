// CodingAgentDetector.swift
// VocaMac
//
// Tells whether the terminal a dictation goes to is running a coding agent
// (Claude Code, Codex, Gemini CLI…), so the text can be cleaned up as the
// prose it is rather than kept exact as a shell command.

import Darwin
import Foundation

/// Whether a terminal app is talking to a coding agent.
///
/// Most dictation into a terminal turned out to be sentences to a coding
/// agent: about 300 of one user's 558 dictations went to Ghostty, nearly all
/// prose to Claude Code. The Terminal style keeps those exact, as if they
/// were commands: no wording edits, and the final period stripped.
///
/// The process tree says what each tab runs: `ghostty → login → zsh →
/// claude`, where `claude` leads its terminal's foreground process group.
/// Only the tab in front matters, and the process tree doesn't say which tab
/// that is, so the decision is:
///
/// - no tab runs an agent in the foreground: not an agent
/// - every tab does: an agent
/// - some do: an agent only when the focused window's title says so. Claude
///   Code titles the tab with its task, behind a status glyph ("✳ Fix the
///   build", "◑ Fix the build"); other agents usually put their name in it.
enum CodingAgentDetector {

    /// Command names of coding agents that take prose in a terminal. Matched
    /// as a whole name ("claude"), or with a "-cli" / "-code" suffix as npm
    /// packages name them ("gemini-cli").
    static let agentNames: Set<String> = [
        "claude", "codex", "aider", "gemini", "opencode", "goose", "amp", "cursor-agent", "crush", "qwen",
    ]

    /// What Claude Code puts before its task in the tab title: the idle mark
    /// and the frames of its working spinner.
    static let titleStatusGlyphs: Set<Character> = ["✳", "✢", "✶", "✻", "✽", "◐", "◓", "◑", "◒"]

    /// One terminal tab: the names its foreground process goes by (its
    /// `argv[0]`, process name, and for an interpreter, its script's path
    /// components), or nil when nothing could be read.
    struct Tab: Equatable {
        var foregroundNames: [String]?
    }

    // MARK: - Decision

    /// Whether `tabs`, the focused window's title, and the rules above say a
    /// coding agent is on the other end of the dictation.
    static func isAgentInFront(tabs: [Tab], windowTitle: String?) -> Bool {
        let agentTabs = tabs.filter { $0.foregroundNames.map(namesAgent) ?? false }
        guard !agentTabs.isEmpty else { return false }
        if agentTabs.count == tabs.count { return true }
        return windowTitle.map(titleSuggestsAgent) ?? false
    }

    /// Whether any of a process's names is a coding agent's.
    static func namesAgent(_ names: [String]) -> Bool {
        names.contains { name in
            let name = name.lowercased()
            return agentNames.contains(name)
                || agentNames.contains { name == "\($0)-cli" || name == "\($0)-code" }
        }
    }

    /// Whether a tab title reads like a coding agent's: one of their names
    /// as a word, or Claude Code's status glyph in front of its task.
    static func titleSuggestsAgent(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if let first = trimmed.first, titleStatusGlyphs.contains(first) { return true }
        let words = trimmed.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "-") }.map(String.init)
        return namesAgent(words)
    }

    // MARK: - Reading the process tree

    /// How deep under the terminal app tabs are looked for: app → login →
    /// shell is two levels; tmux or a nested shell adds a few.
    static let maximumDepth = 6
    /// Most processes walked, so a terminal running a large build stays cheap.
    static let maximumProcesses = 400

    /// Whether the terminal app with `processID` runs a coding agent in the
    /// tab in front. Reads the process table (a few hundred syscalls at most)
    /// and the window title the caller read; call off the main thread.
    static func detect(terminalProcessID: pid_t, windowTitle: String?) -> Bool {
        #if APP_STORE
        // The sandbox doesn't let one app read another's process tree.
        return false
        #else
        isAgentInFront(tabs: tabs(under: terminalProcessID), windowTitle: windowTitle)
        #endif
    }

    #if !APP_STORE
    /// One `Tab` per terminal device used by the processes under `root`.
    private static func tabs(under root: pid_t) -> [Tab] {
        // The foreground process group of each terminal device, as any
        // process on it reports it.
        var foregroundGroups: [UInt32: pid_t] = [:]
        var queue: [(pid: pid_t, depth: Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < maximumProcesses {
            let (pid, depth) = queue.removeFirst()
            visited += 1
            if pid != root, let info = bsdInfo(pid), info.e_tdev != UInt32.max, info.e_tpgid > 0,
               foregroundGroups[info.e_tdev] == nil {
                foregroundGroups[info.e_tdev] = pid_t(info.e_tpgid)
            }
            guard depth < maximumDepth else { continue }
            queue += children(of: pid).map { ($0, depth + 1) }
        }
        // The group's leader is the program the tab runs: `claude`, or the
        // shell when nothing else is in front.
        return foregroundGroups.values.map { Tab(foregroundNames: names(of: $0)) }
    }

    private static func children(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 256)
        let count = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        return count > 0 ? Array(buffer.prefix(Int(count))) : []
    }

    private static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    /// The names a process goes by. Claude Code's process is named for its
    /// version ("2.1.311"), so `argv[0]` matters more than the process name;
    /// a Node or Python agent is named by its script.
    private static func names(of pid: pid_t) -> [String]? {
        let arguments = self.arguments(of: pid)
        var names: [String] = []
        if let info = bsdInfo(pid) {
            names.append(withUnsafeBytes(of: info.pbi_name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) })
        }
        guard let first = arguments.first else { return names.isEmpty ? nil : names }
        let program = (first as NSString).lastPathComponent
        names.append(program)
        if interpreters.contains(where: { program.hasPrefix($0) }),
           let script = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) {
            names += (script as NSString).pathComponents.map { ($0 as NSString).deletingPathExtension }
        }
        return names
    }

    private static let interpreters = ["node", "bun", "deno", "python", "ruby"]

    /// The process's arguments, `argv[0]` first, or empty when the kernel
    /// won't say (another user's process).
    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        // argc, the executable path, padding NULs, then argv.
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while index < size, arguments.count < min(Int(argc), 4) {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
    #endif
}
