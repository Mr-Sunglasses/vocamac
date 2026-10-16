// CalmCommandsDialogs.swift
// VocaMac
//
// The Commands page's dialogs: the Command Mode shortcut recorder, New /
// Edit command (with its own inline shortcut recorder and a delete
// confirmation step, since a dialog can't open another), the Shortcuts
// allow-list for voice actions, How it works, and Try it out.

import CoreGraphics
import SwiftUI

// MARK: - Command Mode shortcut

/// Records the Command Mode shortcut. States (Dialogs board): waiting
/// (accent ring, pulsing), captured, conflict (amber, Save disabled).
/// Saving keys turns Command Mode on; Turn off clears them.
struct CalmCommandShortcutDialog: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.calmDismissDialog) private var dismissDialog

    /// The keys to save: what was pressed, or the current shortcut.
    @State private var candidate: HotKeyCombo?
    @State private var isWaiting: Bool
    /// Drives the hidden key capture; true while the recorder listens.
    @State private var isCapturing = false
    @State private var listenerWasRunning = false
    private let hadShortcut: Bool

    /// - Parameters:
    ///   - current: The shortcut saved now (nil while Command Mode is off).
    ///   - startsWaiting: Open listening for keys (the normal case).
    init(current: HotKeyCombo?, startsWaiting: Bool = true) {
        _candidate = State(initialValue: current)
        _isWaiting = State(initialValue: startsWaiting)
        hadShortcut = current != nil
    }

    var body: some View {
        CalmDialog(
            "Command Mode shortcut",
            description: "Press it once, speak, and press it again. Or hold it while you speak."
        ) {
            keyBox
            if let problem {
                CalmInlineNotice(problem, tone: .warning)
                    .padding(.top, -8)
            } else if !isWaiting, let candidate, let conflict = HotKeyComboRules.systemConflict(candidate) {
                CalmInlineNotice(conflict, tone: .info)
                    .padding(.top, -8)
            }
        } footer: {
            CalmDialogFooter(primaryTitle: "Save", isPrimaryEnabled: canSave, onPrimary: save) {
                leadingAction
            }
        }
        .background {
            CalmCommandKeyCapture(isCapturing: $isCapturing, onCancel: captureCancelled, onCapture: captured)
        }
        .onAppear { if isWaiting { startWaiting() } }
        .onDisappear { stopCapture() }
    }

    private var problem: String? {
        guard !isWaiting, let candidate else { return nil }
        return ShortcutValidation.problem(with: candidate, action: .commandMode, appState: appState)
    }

    private var canSave: Bool { !isWaiting && candidate != nil && problem == nil }

    private var ringColor: Color {
        if isWaiting { return CalmColor.accent }
        return problem == nil ? CalmColor.line2 : CalmColor.amber
    }

    private var keyBox: some View {
        Button(action: startWaiting) {
            CalmCommandKeyBox(ring: ringColor, isPulsing: isWaiting) {
                if isWaiting {
                    Text("Press the keys you want…").font(.system(size: 14)).foregroundStyle(CalmColor.muted)
                } else if let candidate {
                    CalmKeyCombo(combo: candidate, size: .large)
                    if problem == nil {
                        Text("Press again to change").font(.system(size: 12)).foregroundStyle(CalmColor.muted)
                    }
                } else {
                    Text("No shortcut yet").font(.system(size: 14)).foregroundStyle(CalmColor.muted)
                    Text("Click to record one").font(.system(size: 12)).foregroundStyle(CalmColor.muted)
                }
            }
        }
        .buttonStyle(CalmPlainFocusStyle(radius: 12))
        .focusEffectDisabled()
        .accessibilityLabel(isWaiting ? "Press the keys you want" : "Record the Command Mode shortcut")
        .accessibilityValue(candidate.map { KeyCodeReference.displayName(for: $0) } ?? "None")
    }

    @ViewBuilder
    private var leadingAction: some View {
        if hadShortcut {
            Button("Turn off") {
                stopCapture()
                appState.setCommandModeOn(false)
                dismissDialog?()
            }
            .calmButton(.quiet)
            .help("Clears the shortcut. The switch puts it back.")
        } else if let suggestion = ShortcutValidation.suggestion(for: .commandMode, appState: appState),
                  suggestion != candidate {
            Button("Use \(CalmCommandsText.keys(suggestion))") {
                stopCapture()
                isWaiting = false
                candidate = suggestion
            }
            .calmButton(.quiet)
            .help("Three modifiers, which other apps rarely use")
        }
    }

    // MARK: Capture

    private func startWaiting() {
        guard !isCapturing else { return }
        isWaiting = true
        listenerWasRunning = appState.beginCommandShortcutCapture()
        isCapturing = true
    }

    private func stopCapture() {
        guard isCapturing || appState.isCapturingShortcut else { return }
        isCapturing = false
        appState.endCommandShortcutCapture(restartListener: listenerWasRunning)
        listenerWasRunning = false
    }

    private func captured(_ combo: HotKeyCombo) {
        candidate = combo
        isWaiting = false
        appState.endCommandShortcutCapture(restartListener: listenerWasRunning)
        listenerWasRunning = false
    }

    /// Escape closes the dialog, as everywhere else; Tab or the window
    /// losing focus just stop listening.
    private func captureCancelled() {
        appState.endCommandShortcutCapture(restartListener: listenerWasRunning)
        listenerWasRunning = false
        isWaiting = false
        if CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(KeyCodeReference.escapeKeyCode)) {
            dismissDialog?()
        }
    }

    private func save() {
        guard let candidate, problem == nil else { return }
        appState.setShortcut(candidate, for: .commandMode)
    }
}

// MARK: - New / Edit command

/// New command or Edit command: name, instruction and an optional
/// shortcut recorded in place. Editing adds Delete far left; deleting a
/// command with a shortcut asks first, in the same dialog.
struct CalmSavedCommandDialog: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.calmDismissDialog) private var dismissDialog

    @State private var draft: CalmSavedCommandDraft
    @State private var isConfirmingDelete: Bool
    @State private var isRecording = false
    @State private var listenerWasRunning = false
    @FocusState private var isNameFocused: Bool
    private let startsRecording: Bool

    init(draft: CalmSavedCommandDraft, startsConfirmingDelete: Bool = false, startsRecording: Bool = false) {
        _draft = State(initialValue: draft)
        _isConfirmingDelete = State(initialValue: startsConfirmingDelete)
        self.startsRecording = startsRecording
    }

    var body: some View {
        Group {
            if isConfirmingDelete {
                confirmation
            } else {
                editor
            }
        }
        .background {
            CalmCommandKeyCapture(isCapturing: $isRecording, onCancel: recordingCancelled, onCapture: recorded)
        }
        .onAppear {
            if startsRecording {
                startRecording()
            } else if draft.isNew {
                DispatchQueue.main.async { isNameFocused = true }
            }
        }
        .onDisappear { stopRecording() }
    }

    // MARK: Editor

    private var editor: some View {
        let commands = appState.savedCommands
        return CalmDialog(draft.isNew ? "New command" : "Edit command", description: "Saved commands run on selected text.") {
            CalmTextField(
                "Name", text: $draft.name, prompt: "e.g. Shorter",
                error: draft.nameProblem(in: commands), focus: $isNameFocused
            )
            CalmTextEditor(
                "Instruction", text: $draft.instruction,
                prompt: "e.g. Cut this to half the length without losing facts."
            )
            // Label + 6 + the 88-point field; a TextEditor would otherwise fill the window.
            .frame(height: 110)
            shortcutRow
        } footer: {
            CalmDialogFooter(
                primaryTitle: draft.isNew ? "Create" : "Save",
                isPrimaryEnabled: canSave(commands),
                onPrimary: { appState.saveCommandDraft(draft) },
                leading: {
                    if !draft.isNew {
                        Button("Delete", action: delete).calmButton(.quietAmber)
                    }
                }
            )
        }
    }

    private func canSave(_ commands: [SavedCommand]) -> Bool {
        draft.isValid(in: commands) && !isRecording && shortcutProblem == nil
    }

    private var shortcutProblem: String? {
        guard let combo = draft.shortcut else { return nil }
        return ShortcutValidation.problem(with: combo, action: .savedCommand(draft.id), appState: appState)
    }

    private var shortcutRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shortcut").calmType(.rowTitle).foregroundStyle(CalmColor.ink)
                    Text(draft.shortcut == nil && !isRecording ? "Optional" : "Runs it without speaking")
                        .calmType(.description)
                        .foregroundStyle(CalmColor.muted)
                }
                Spacer(minLength: 0)
                shortcutControl
                    .fixedSize()
            }
            if let shortcutProblem, !isRecording {
                CalmInlineNotice(shortcutProblem, tone: .warning)
            }
        }
    }

    @ViewBuilder
    private var shortcutControl: some View {
        if isRecording {
            HStack(spacing: 8) {
                CalmRecordingKeyCap()
                Button("Cancel", action: stopRecording).calmButton(.quiet, size: .small)
            }
        } else if let combo = draft.shortcut {
            HStack(spacing: 8) {
                Button(action: startRecording) { CalmKeyCombo(combo: combo) }
                    .buttonStyle(CalmPlainFocusStyle(radius: 8))
                    .focusEffectDisabled()
                    .help("Record different keys")
                    .accessibilityLabel("Shortcut \(KeyCodeReference.displayName(for: combo)). Change")
                Button("Remove") { draft.shortcut = nil }
                    .calmButton(.quiet, size: .small)
            }
        } else {
            Button("Record shortcut", action: startRecording).calmButton(.secondary)
        }
    }

    // MARK: Delete

    private var savedCommand: SavedCommand? { appState.savedCommands.first { $0.id == draft.id } }

    private var confirmation: some View {
        let name = savedCommand.map(CalmCommandsText.commandName) ?? CalmCommandsText.commandName(
            SavedCommand(name: draft.name, instruction: draft.instruction)
        )
        let keys = savedCommand.flatMap { HotKeyCombo(storageString: $0.shortcut) }
            .map(CalmCommandsText.keys)
        let description = keys.map { "Its shortcut \($0) stops working. Your other commands are kept." }
            ?? "Your other commands are kept."
        return CalmDialog("Delete “\(name)”?", description: description) {
            CalmDialogFooter(
                primaryTitle: "Delete", primaryKind: .destructive,
                onCancel: { isConfirmingDelete = false },
                onPrimary: { appState.deleteSavedCommand(draft.id) }
            )
        }
    }

    /// Delete straight away, unless the command has a shortcut someone may
    /// rely on without looking.
    private func delete() {
        stopRecording()
        if let savedCommand, HotKeyCombo(storageString: savedCommand.shortcut) != nil {
            isConfirmingDelete = true
        } else {
            appState.deleteSavedCommand(draft.id)
            dismissDialog?()
        }
    }

    // MARK: Recording

    private func startRecording() {
        guard !isRecording else { return }
        listenerWasRunning = appState.beginCommandShortcutCapture()
        isRecording = true
    }

    private func stopRecording() {
        guard isRecording || appState.isCapturingShortcut else { return }
        isRecording = false
        appState.endCommandShortcutCapture(restartListener: listenerWasRunning)
        listenerWasRunning = false
    }

    private func recorded(_ combo: HotKeyCombo) {
        draft.shortcut = combo
        appState.endCommandShortcutCapture(restartListener: listenerWasRunning)
        listenerWasRunning = false
    }

    /// Escape or a lost focus only stops recording; the dialog stays.
    private func recordingCancelled() {
        appState.endCommandShortcutCapture(restartListener: listenerWasRunning)
        listenerWasRunning = false
    }
}

// MARK: - Shortcuts VocaMac may run

/// The voice-action allow-list: Shortcuts names, one per line.
struct CalmVoiceShortcutsDialog: View {
    @EnvironmentObject private var appState: AppState
    @State private var text: String

    init(text: String) {
        _text = State(initialValue: text)
    }

    var body: some View {
        CalmDialog(
            "Shortcuts VocaMac may run",
            description: "One name per line, as it appears in the Shortcuts app. A shortcut that isn’t listed never runs. Selected text is passed to it as its input."
        ) {
            CalmTextEditor(nil, text: $text, prompt: "Morning routine\nLog water", minHeight: 120)
                .frame(height: 120)
                .accessibilityLabel("Shortcuts VocaMac may run, one per line")
        } footer: {
            CalmDialogFooter(primaryTitle: "Save") {
                appState.voiceActionShortcuts = SavedCommandStore.shortcutNames(from: text).joined(separator: "\n")
            }
        }
    }
}

// MARK: - How it works

/// How Command Mode works, step by step, with the wider set of examples.
struct CalmCommandsHowItWorksDialog: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let caps = appState.shortcut(for: .commandMode).map(CalmKeyCaps.labels(for:))
        CalmDialog("How Command Mode works", width: CalmMetrics.dialogListWidth) {
            VStack(alignment: .leading, spacing: 14) {
                step(1) {
                    Text("Select text in any app.")
                }
                step(2) {
                    if let caps {
                        CalmKeyedLine(
                            [.text("Press"), .keys(caps), .text("once, or hold it while you speak.")],
                            spacing: 5, capSize: .inline, font: CalmFont.body, color: CalmColor.ink
                        )
                    } else {
                        Text("Press the Command Mode shortcut once, or hold it while you speak. Set one in the page header.")
                    }
                }
                step(3) {
                    Text("Say what to change. With nothing selected, say what to write and it’s typed where the cursor is.")
                }
                step(4) {
                    Text(reviewLine)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Things to try").calmType(.caption).foregroundStyle(CalmColor.muted)
                FlowLayout(spacing: 6) {
                    ForEach(CalmCommandsText.moreExamples, id: \.self) { example in
                        Text("“\(example)”")
                            .font(CalmFont.description.italic())
                            .foregroundStyle(CalmColor.ink2)
                            .fixedSize()
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(CalmColor.panel2))
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } footer: {
            CalmDialogFooter(primaryTitle: "Done", cancelTitle: nil) {}
        }
    }

    private var reviewLine: String {
        switch appState.commandModeReview {
        case .never:
            return "The selection is replaced straight away. Saying “undo” puts your text back."
        case .longSelections:
            return "Long edits show a preview first: press the shortcut again to replace, or Esc to discard. Saying “undo” puts your text back."
        case .always:
            return "Every edit shows a preview first: press the shortcut again to replace, or Esc to discard. Saying “undo” puts your text back."
        }
    }

    private func step<Content: View>(_ number: Int, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(CalmFont.sf(12, weight: 650))
                .foregroundStyle(CalmColor.ink2)
                .frame(width: 22, height: 22)
                .background(Circle().fill(CalmColor.panel2))
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            content()
                .font(CalmFont.body)
                .foregroundStyle(CalmColor.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Try it out

/// Practice text to edit by voice, right here.
struct CalmCommandsTryDialog: View {
    let onSetShortcut: () -> Void

    @EnvironmentObject private var appState: AppState
    @State private var text = CalmCommandsTryDialog.sample

    static let sample = "hey team so basically the launch is moving to thursday because the build wasnt ready and we want more time to test it properly, sorry for the late notice"

    var body: some View {
        let combo = appState.shortcut(for: .commandMode)
        CalmDialog("Try it out") {
            if let combo {
                VStack(alignment: .leading, spacing: 6) {
                    CalmKeyedLine(
                        [.text("Select some of the text below, press"), .keys(CalmKeyCaps.labels(for: combo)), .text("and say")],
                        spacing: 5, capSize: .inline
                    )
                    Text("“make this shorter” or “fix the grammar”.").calmType(.description).foregroundStyle(CalmColor.muted)
                }
            } else {
                CalmInlineNotice("Command Mode needs a shortcut first.", tone: .warning)
            }
            CalmTextEditor(nil, text: $text, minHeight: 110)
                .frame(height: 110)
                .accessibilityLabel("Practice text")
        } footer: {
            CalmDialogFooter(primaryTitle: "Done", cancelTitle: nil, onPrimary: {}, leading: {
                if combo == nil {
                    Button("Set shortcut", action: onSetShortcut).calmButton(.quiet)
                } else if text != Self.sample {
                    Button("Start over") { text = Self.sample }.calmButton(.quiet)
                }
            })
        }
    }
}

// MARK: - Recorder pieces

/// The recorder's key box: 96 high, r12, panel fill, a 1.5 pt ring, and a
/// soft accent halo that pulses while it listens.
struct CalmCommandKeyBox<Content: View>: View {
    let ring: Color
    var isPulsing = false
    let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    init(ring: Color, isPulsing: Bool = false, @ViewBuilder content: () -> Content) {
        self.ring = ring
        self.isPulsing = isPulsing
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        VStack(spacing: 8) { content }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background(shape.fill(CalmColor.panel))
            .overlay(shape.strokeBorder(ring, lineWidth: 1.5))
            .overlay {
                if isPulsing {
                    RoundedRectangle(cornerRadius: 15.5, style: .continuous)
                        .strokeBorder(CalmColor.accentSoft, lineWidth: 3.5)
                        .padding(-3.5)
                        .opacity(pulse ? 0.2 : 1)
                        .onAppear {
                            guard !reduceMotion else { return }
                            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulse = true }
                        }
                        .onDisappear { pulse = false }
                        .allowsHitTesting(false)
                }
            }
            .contentShape(shape)
    }
}

/// The hidden key capture behind a recorder: an event tap while
/// `isCapturing` is on (see `HotKeyRecorderButton`).
private struct CalmCommandKeyCapture: View {
    @Binding var isCapturing: Bool
    let onCancel: () -> Void
    let onCapture: (HotKeyCombo) -> Void

    var body: some View {
        HotKeyRecorderButton(isRecording: $isCapturing, onStart: {}, onCancel: onCancel, onKeyRecorded: onCapture)
            .frame(width: 0, height: 0)
            .opacity(0)
            .disabled(true)
            .accessibilityHidden(true)
    }
}
