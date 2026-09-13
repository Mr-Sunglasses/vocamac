// MeetingCaptureView.swift
// VocaMac

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MeetingCaptureWindowManager: NSObject, ObservableObject, NSWindowDelegate {
    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    /// Owned here rather than by the view, so closing the window can ask
    /// before throwing a capture away.
    private var capture: SystemAudioCapture?

    func open(appState: AppState) {
        if let window, window.isVisible { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 350),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.contentMinSize = NSSize(width: 500, height: 310)
        window.title = "System Audio Transcription"
        let capture = SystemAudioCapture()
        window.contentView = NSHostingView(rootView: MeetingCaptureView(capture: capture).environmentObject(appState))
        window.delegate = self
        window.center(); window.isReleasedWhenClosed = false; window.makeKeyAndOrderFront(nil)
        self.window = window
        self.capture = capture
        DockVisibilityCoordinator.shared.windowDidOpen(); NSApp.activate(ignoringOtherApps: true)
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.window = nil
                if let capture = self.capture, capture.isCapturing { _ = capture.stop() }
                self.capture = nil
                if let closeObserver = self.closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
                self.closeObserver = nil
                DockVisibilityCoordinator.shared.windowDidClose()
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let capture, capture.isCapturing else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard the system-audio capture?"
        alert.informativeText = "Closing this window stops the capture and throws away the audio recorded so far. Use Stop and Transcribe to keep it."
        alert.addButton(withTitle: "Keep Capturing")
        alert.addButton(withTitle: "Discard and Close")
        return alert.runModal() == .alertSecondButtonReturn
    }
}

struct MeetingCaptureView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var capture: SystemAudioCapture
    @State private var result: VocaTranscription?
    /// The last capture, kept until it is transcribed so a failed attempt
    /// (the speech model busy or unavailable) can be retried.
    @State private var capturedSamples: [Float]?
    @State private var error: String?
    @State private var notice: String?
    @State private var isTranscribing = false
    @State private var startedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TranscriptionWorkflowHeader(
                title: "System Audio",
                subtitle: "Capture what this Mac is playing, then transcribe it locally.",
                systemImage: "speaker.wave.2"
            )
            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.subheadline.weight(.medium))
                    if capture.isCapturing, let startedAt {
                        TimelineView(.periodic(from: startedAt, by: 1)) { context in
                            Text(elapsedDescription(since: startedAt, now: context.date))
                                .font(.caption2)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(statusDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(capture.isCapturing ? "Stop and Transcribe" : "Start Capture") {
                    capture.isCapturing ? stop() : start()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isTranscribing || appState.isRecording)
                if isTranscribing { ProgressView().controlSize(.small) }
            }
            .vocaCard()
            Label("Private capture · no virtual driver · 20-minute limit", systemImage: "lock.shield")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let result {
                WorkflowTranscriptCard(
                    text: result.text,
                    detail: "\(String(format: "%.1f", result.audioLengthSeconds))s audio · \(String(format: "%.1f", result.duration))s processing · \(result.detectedLanguage)",
                    copy: { copy(result.text) },
                    save: { save(result.text) }
                )
            }
            if let error {
                HStack(spacing: 10) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    if capturedSamples != nil, !isTranscribing, !capture.isCapturing {
                        Button("Try Again") { transcribeCapture() }
                            .controlSize(.small)
                    }
                }
            }
            if let notice {
                Label(notice, systemImage: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VocaDesign.canvas)
        .tint(VocaDesign.accent)
        .onChange(of: capture.didReachLimit) {
            if capture.didReachLimit, !isTranscribing { stop() }
        }
    }

    private func start() {
        error = nil
        notice = nil
        result = nil
        capturedSamples = nil
        do {
            try capture.start()
            startedAt = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func elapsedDescription(since start: Date, now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(start)))
        let limit = SystemAudioAccumulator.maximumDurationSeconds
        return String(format: "%d:%02d of %d:00 · playback continues normally", elapsed / 60, elapsed % 60, limit / 60)
    }

    private func stop() {
        startedAt = nil
        let samples = capture.stop()
        guard !samples.isEmpty else { error = "No system audio was captured."; return }
        guard !SystemAudioAccumulator.isSilent(samples) else {
            error = "Only silence was captured. Play audio while capturing, and allow VocaMac under System Settings → Privacy & Security → Screen & System Audio Recording."
            return
        }
        if capture.didReachLimit {
            notice = "The 20-minute limit was reached; the retained audio is being transcribed."
        }
        capturedSamples = samples
        transcribeCapture()
    }

    private func transcribeCapture() {
        guard let samples = capturedSamples else { return }
        error = nil
        isTranscribing = true
        Task { @MainActor in
            do {
                result = try await appState.transcribeCapturedAudio(samples)
                capturedSamples = nil
            } catch {
                self.error = error.localizedDescription
            }
            isTranscribing = false
        }
    }

    private var statusTitle: String {
        if capture.isCapturing { return "Capturing system audio" }
        if isTranscribing { return "Transcribing capture" }
        if capturedSamples != nil { return "Capture not transcribed yet" }
        return "Ready to capture"
    }

    private var statusDetail: String {
        if capture.isCapturing { return "Playback continues normally" }
        if isTranscribing { return "Processing locally with the selected speech model" }
        return "Uses the currently selected speech model"
    }

    private var statusColor: Color {
        if capture.isCapturing { return .red }
        if isTranscribing { return VocaDesign.accent }
        return VocaDesign.success
    }

    private func save(_ text: String) {
        let panel = NSSavePanel()
        panel.title = "Save Transcript"
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "System Audio Transcript.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8) }
        catch { self.error = "Could not save the transcript: \(error.localizedDescription)" }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
