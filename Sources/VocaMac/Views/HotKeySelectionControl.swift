// HotKeySelectionControl.swift
// VocaMac
//
// Reusable hotkey picker with direct key recording for settings and onboarding.

import AppKit
import CoreGraphics
import SwiftUI

struct HotKeySelectionControl: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRecording = false
    @State private var wasListeningBeforeRecording = false

    let pickerLabel: String
    let footerText: String?

    init(pickerLabel: String = "Preset", footerText: String? = nil) {
        self.pickerLabel = pickerLabel
        self.footerText = footerText
    }

    private var comboBinding: Binding<HotKeyCombo> {
        Binding(
            get: { HotKeyCombo(keyCode: appState.hotKeyCode, modifiers: appState.hotKeyModifiers) },
            set: { newCombo in
                appState.hotKeyCode = newCombo.keyCode
                appState.hotKeyModifiers = newCombo.modifiers
                guard !isRecording else { return }
                appState.syncHotKeyConfiguration()
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker(pickerLabel, selection: comboBinding) {
                    ForEach(KeyCodeReference.commonHotKeys, id: \.name) { hotKey in
                        Text(hotKey.name).tag(HotKeyCombo(keyCode: hotKey.keyCode, modifiers: hotKey.modifiers))
                    }

                    let currentCombo = HotKeyCombo(keyCode: appState.hotKeyCode, modifiers: appState.hotKeyModifiers)
                    if !KeyCodeReference.isCommonHotKey(currentCombo) {
                        Divider()
                        Text("Custom: \(KeyCodeReference.displayName(for: currentCombo))")
                            .tag(currentCombo)
                    }
                }
                .disabled(isRecording)

                HotKeyRecorderButton(
                    isRecording: $isRecording,
                    onStart: beginRecording,
                    onCancel: finishRecording,
                    onKeyRecorded: recordKey
                )
            }

            if isRecording {
                Label("Press a key, or press Escape to cancel", systemImage: "keyboard")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            } else if let footerText {
                Text(footerText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onDisappear {
            guard isRecording else { return }
            isRecording = false
            finishRecording()
        }
    }

    private func beginRecording() {
        wasListeningBeforeRecording = appState.hotKeyManager.isListening
        if wasListeningBeforeRecording {
            appState.hotKeyManager.stopListening()
        }
    }

    private func finishRecording() {
        if wasListeningBeforeRecording {
            restartHotKeyListener()
        }
        wasListeningBeforeRecording = false
    }

    private func recordKey(_ combo: HotKeyCombo) {
        appState.hotKeyCode = combo.keyCode
        appState.hotKeyModifiers = combo.modifiers
        appState.syncHotKeyConfiguration()
        finishRecording()
    }

    private func restartHotKeyListener() {
        appState.hotKeyManager.startListening(
            keyCode: appState.hotKeyCode,
            mode: appState.activationMode,
            doubleTapThreshold: appState.doubleTapThreshold,
            safetyTimeout: Double(appState.maxRecordingDuration) + 5.0,
            modifiers: appState.hotKeyModifiers
        )
    }
}

private struct HotKeyRecorderButton: View {
    @Binding var isRecording: Bool

    let onStart: () -> Void
    let onCancel: () -> Void
    let onKeyRecorded: (HotKeyCombo) -> Void

    var body: some View {
        ZStack {
            Button {
                if isRecording {
                    isRecording = false
                    onCancel()
                } else {
                    onStart()
                    isRecording = true
                }
            } label: {
                Label(isRecording ? "Cancel" : "Record", systemImage: isRecording ? "xmark.circle" : "record.circle")
            }
            .controlSize(.small)

            if isRecording {
                HotKeyCaptureView(
                    onCapture: { combo in
                        isRecording = false
                        onKeyRecorded(combo)
                    },
                    onCancel: {
                        isRecording = false
                        onCancel()
                    }
                )
                .frame(width: 1, height: 1)
                .opacity(0)
                .accessibilityHidden(true)
            }
        }
    }
}

private struct HotKeyCaptureView: NSViewRepresentable {
    let onCapture: (HotKeyCombo) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> HotKeyCaptureNSView {
        let view = HotKeyCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: HotKeyCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        nsView.focus()
    }

    static func dismantleNSView(_ nsView: HotKeyCaptureNSView, coordinator: ()) {
        nsView.stopMonitoring()
    }
}

private final class HotKeyCaptureNSView: NSView {
    var onCapture: ((HotKeyCombo) -> Void)?
    var onCancel: (() -> Void)?

    private var localMonitor: Any?
    private var windowResignObserver: NSObjectProtocol?
    private var didCapture = false

    /// Key code of a modifier that was pressed while it was the *only*
    /// modifier held — a candidate for a legacy lone-modifier hotkey. Cleared
    /// as soon as a second modifier joins it, so a chord (e.g. holding
    /// Control then Shift) is never mistaken for a completed tap.
    private var singleModifierCandidateKeyCode: Int?

    /// Physical modifier key codes currently believed held, tracked per key
    /// (not per shared flag) so pressing both Left and Right Shift is
    /// correctly seen as two distinct keys even though they share one
    /// NSEvent.ModifierFlags bit.
    private var heldModifierKeyCodes: Set<Int> = []

    private static let modifierKeyCodes = [54, 55, 56, 58, 59, 60, 61, 62, 63]

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        seedHeldModifiers()
        installMonitor()
        installWindowObserver()
        focus()
    }

    /// Reads the *actual* current physical key state so a modifier already
    /// held down before the user clicks "Record" (e.g. holding Command with
    /// the other hand) is known from the start, rather than assumed absent.
    private func seedHeldModifiers() {
        let held = Self.modifierKeyCodes.filter {
            CGEventSource.keyState(.combinedSessionState, key: CGKeyCode($0))
        }
        heldModifierKeyCodes = Set(held)
        singleModifierCandidateKeyCode = held.count == 1 ? held[0] : nil
    }

    override func keyDown(with event: NSEvent) {
        _ = capture(event)
    }

    override func flagsChanged(with event: NSEvent) {
        _ = capture(event)
    }

    func focus() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    func stopMonitoring() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        if let windowResignObserver {
            NotificationCenter.default.removeObserver(windowResignObserver)
            self.windowResignObserver = nil
        }
    }

    private func installMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else { return event }
            return self.capture(event) ? nil : event
        }
    }

    private func installWindowObserver() {
        guard windowResignObserver == nil, let window else { return }
        windowResignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            self?.cancelCapture()
        }
    }

    private func capture(_ event: NSEvent) -> Bool {
        guard !didCapture else { return false }

        if shouldCancel(event) {
            cancelCapture()
            return true
        }

        switch event.type {
        case .keyDown:
            guard !event.isARepeat else { return false }
            // A non-modifier key press always finalizes immediately, using
            // whatever modifiers are currently held (possibly none).
            let combo = HotKeyCombo(keyCode: Int(event.keyCode), modifiers: HotKeyModifiers(nsFlags: event.modifierFlags))
            finalizeCapture(with: combo)
            return true

        case .flagsChanged:
            return handleFlagsChanged(event)

        default:
            return false
        }
    }

    /// Tracks modifier presses/releases per physical key so a chord (e.g.
    /// holding Control then Shift, then pressing Space) can be composed
    /// before finalizing, while a lone modifier tap (press-then-release with
    /// nothing else) still finalizes as the legacy single-modifier hotkey.
    /// A flagsChanged event's `keyCode` always identifies the specific
    /// physical key that changed, even when its shared modifier flag (e.g.
    /// `.shift`) was already set by the other key in its left/right pair —
    /// tracking by key code (rather than by flag) keeps Left+Right presses
    /// of the same modifier from being conflated into a single toggle.
    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        let keyCode = Int(event.keyCode)
        guard KeyCodeReference.isModifierKeyCode(keyCode) else { return false }

        if heldModifierKeyCodes.remove(keyCode) != nil {
            // This physical key was released.
            guard heldModifierKeyCodes.isEmpty else { return false }
            if singleModifierCandidateKeyCode == keyCode {
                finalizeCapture(with: HotKeyCombo(keyCode: keyCode, modifiers: []))
                return true
            }
            singleModifierCandidateKeyCode = nil
            return false
        }

        // This physical key was pressed. Only a press from zero-held is a
        // lone-modifier candidate; anything joining an existing hold is
        // building a chord and cancels any prior candidacy.
        singleModifierCandidateKeyCode = heldModifierKeyCodes.isEmpty ? keyCode : nil
        heldModifierKeyCodes.insert(keyCode)
        return false
    }

    private func finalizeCapture(with combo: HotKeyCombo) {
        didCapture = true
        stopMonitoring()
        DispatchQueue.main.async { [weak self] in
            self?.onCapture?(combo)
        }
    }

    private func cancelCapture() {
        guard !didCapture else { return }
        didCapture = true
        stopMonitoring()
        DispatchQueue.main.async { [weak self] in
            self?.onCancel?()
        }
    }

    private func shouldCancel(_ event: NSEvent) -> Bool {
        event.type == .keyDown && Int(event.keyCode) == KeyCodeReference.escapeKeyCode
    }

    deinit {
        stopMonitoring()
    }
}

// MARK: - HotKeyModifiers Conversion

extension HotKeyModifiers {
    /// Maps the 5 relevant NSEvent.ModifierFlags bits (Control/Option/Shift/
    /// Command/Fn) into our own canonical representation.
    init(nsFlags flags: NSEvent.ModifierFlags) {
        var result: HotKeyModifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.function) { result.insert(.function) }
        self = result
    }
}
