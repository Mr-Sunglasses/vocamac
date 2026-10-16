// MenuBarView.swift
// VocaMac
//
// The panel shown when clicking the menu bar icon: live status, the
// choices for the next dictation, the last dictation, and quick actions.

import SwiftUI

// MARK: - Process Monitor

/// Polls the current process for CPU and memory usage every 5 seconds.
@MainActor
final class ProcessMonitor: ObservableObject {
    @Published var cpuUsage: Double = 0       // percentage (0–100+)
    @Published var memoryMB: Double = 0       // resident memory in MB
    @Published var memoryPeakMB: Double = 0   // peak memory seen
    @Published var threadCount: Int = 0       // active thread count

    /// nonisolated(unsafe): read once more by `deinit`, which can't be
    /// main-actor isolated on macOS 14.
    nonisolated(unsafe) private var timer: Timer?

    init(useTimer: Bool = true) {
        if useTimer {
            start()
        }
    }

    deinit { timer?.invalidate() }

    /// Poll only while a resource-usage view is visible.
    func start() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop.
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One-shot resident memory sample for the current process (MB).
    nonisolated static func currentResidentMemoryMB() -> Double {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return Double(taskInfo.resident_size) / (1024 * 1024)
    }

    func refresh() {
        // --- Memory via mach_task_basic_info ---
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kr = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let mb = Double(taskInfo.resident_size) / (1024 * 1024)
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.memoryMB = mb
                    self.memoryPeakMB = max(self.memoryPeakMB, mb)
                }
            }
        }

        // --- CPU via task_threads + thread_basic_info ---
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        let threadKr = task_threads(mach_task_self_, &threadList, &threadCount)
        guard threadKr == KERN_SUCCESS, let threads = threadList else { return }

        var totalCPU: Double = 0
        for i in 0..<Int(threadCount) {
            var threadInfo = thread_basic_info()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
            let infoKr = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if infoKr == KERN_SUCCESS && threadInfo.flags != TH_FLAGS_IDLE {
                totalCPU += Double(threadInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
            // task_threads gives the caller a send right for every thread.
            // Releasing only the array leaks one right per sampled thread.
            mach_port_deallocate(mach_task_self_, threads[i])
        }

        let count2 = Int(threadCount)
        // Deallocate the thread list
        let size = vm_size_t(MemoryLayout<thread_t>.stride * Int(threadCount))
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)

        let cpu = totalCPU
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.cpuUsage = cpu
                self?.threadCount = count2
            }
        }
    }
}

/// The menu bar panel, in the v3 menu style: a live status line (dot, state,
/// model), the notices and choices for the next dictation, then rows like a
/// native menu (h30, r6, hover panel2, shortcut on the right).
struct MenuBarView: View {
    /// Confirmation text after binding or clearing a style, if any.
    @State private var bindNotice: String?
    @State private var panelWindow = MenuPanelWindowReference()

    @EnvironmentObject var appState: AppState
    @ObservedObject var settingsManager: SettingsWindowManager
    @ObservedObject private var gateway = GatewayEmbedController.shared
    @ObservedObject var updateWindowManager: UpdateWindowManager
    @ObservedObject var fileTranscriptionManager: FileTranscriptionWindowManager
    @ObservedObject var scratchpadManager: ScratchpadWindowManager
    @ObservedObject var meetingCaptureManager: MeetingCaptureWindowManager
    @State private var audioDevices: [AudioDevice] = []
    @State private var availableHeight: CGFloat = 640
    /// Measured heights of the scrolling middle and the pinned top and bottom.
    @State private var contentHeight: CGFloat = 0
    @State private var chromeHeight: CGFloat = 0

    /// MenuBarExtra sizes its window to the view's ideal size, and a
    /// ScrollView has no ideal height of its own — left flexible it collapses
    /// to nothing, and pinned to the screen it leaves dead space under short
    /// content. Give it exactly its content's height, capped so the whole
    /// panel still fits on the display.
    private var scrollHeight: CGFloat {
        max(0, min(contentHeight, availableHeight - chromeHeight))
    }

    private var contentOverflows: Bool {
        contentHeight > availableHeight - chromeHeight + 0.5
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                statusSection
                MenuSeparator()
                primaryRows
                MenuSeparator()
            }
            .fixedSize(horizontal: false, vertical: true)
            .measureHeight(MenuChromeHeightKey.self)

            ScrollView {
                supplementaryContent
                    .measureHeight(MenuContentHeightKey.self)
            }
            .scrollIndicators(contentOverflows ? .automatic : .never)
            .frame(height: scrollHeight)

            VStack(spacing: 0) {
                MenuSeparator()
                actionsSection
            }
            .fixedSize(horizontal: false, vertical: true)
            .measureHeight(MenuChromeHeightKey.self)
        }
        .padding(MenuPanelMetrics.padding)
        .frame(width: MenuPanelMetrics.width)
        .background(CalmColor.content)
        .clipShape(RoundedRectangle(cornerRadius: MenuPanelMetrics.panelRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MenuPanelMetrics.panelRadius, style: .continuous)
                .strokeBorder(CalmColor.line2, lineWidth: 1)
        )
        .background(MenuPanelWindowSizer(
            height: chromeHeight + scrollHeight + MenuPanelMetrics.padding * 2,
            onWindow: { panelWindow.window = $0 }
        ))
        .onPreferenceChange(MenuContentHeightKey.self) { contentHeight = $0 }
        .onPreferenceChange(MenuChromeHeightKey.self) { chromeHeight = $0 }
        .tint(CalmColor.accent)
        .onAppear {
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            availableHeight = min(720, (screen?.visibleFrame.height ?? 760) - 40) - MenuPanelMetrics.padding * 2
            bindNotice = nil
            appState.refreshActiveWritingStyle(readingWebsite: true)
            Task { await gateway.refreshStatus() }
        }
        // A "saved for Ghostty" notice is wrong once the user is in Discord.
        .onChange(of: appState.activeWritingTargetName) { _, _ in bindNotice = nil }
    }

    // MARK: - Status

    /// The menu's first line is live status: dot, state, model. What the
    /// state needs (a download, the live words, an error and its fix)
    /// follows directly under it.
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                MenuStatusDot(
                    color: statusColor,
                    isActive: appState.appStatus == .recording || appState.appStatus == .processing
                )
                Text(statusText)
                    .font(CalmFont.statusTitle)
                    .foregroundStyle(CalmColor.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                modelLabel
            }
            .padding(EdgeInsets(top: 8, leading: 10, bottom: 6, trailing: 10))

            if hasStatusDetails {
                statusDetails
                    .padding(.horizontal, 10)
                    .padding(.top, 2)
                    .padding(.bottom, 6)
            }
        }
    }

    /// Whether anything shows under the status line, so an idle menu has
    /// no empty gap there.
    private var hasStatusDetails: Bool {
        let downloading = appState.currentModel == nil && !appState.whisperService.isModelLoaded
            && appState.availableModels.contains { $0.downloadProgress != nil }
        let commandHint = appState.appStatus == .idle && appState.shortcut(for: .commandMode) != nil
        let unload = appState.modelUnloadStatusMessage != nil && (appState.appStatus == .idle || appState.isAutoPaused)
        let error = appState.errorNotice != nil && (appState.appStatus == .idle || appState.appStatus == .error)
        return downloading || commandHint || unload || error
            || appState.commandModeSession != nil || appState.appStatus == .recording
    }

    @ViewBuilder
    private var modelLabel: some View {
        Group {
            if let model = appState.currentModel {
                Text(model.size.isRemotelyHosted ? "\(model.size.displayName) · Remote" : model.size.displayName)
            } else if appState.whisperService.isModelLoaded {
                Text(appState.loadedModelDisplayName ?? "Model loaded")
            } else if let downloading = appState.availableModels.first(where: { $0.downloadProgress != nil }),
                      let progress = downloading.downloadProgress {
                Text("Downloading \(Int(progress * 100))%")
            } else if let loading = appState.availableModels.first(where: { $0.isLoading }) {
                Text("Loading \(loading.size.displayName)…")
            } else if appState.isAutoPaused || appState.lastModelUnloadReason == .idleKeepAlive {
                Text("Model unloaded")
            } else {
                Text("No model loaded").foregroundStyle(CalmColor.amber)
            }
        }
        .font(CalmFont.note)
        .foregroundStyle(CalmColor.muted)
        .lineLimit(1)
        .truncationMode(.middle)
    }

    @ViewBuilder
    private var statusDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            if appState.currentModel == nil, !appState.whisperService.isModelLoaded,
               let downloading = appState.availableModels.first(where: { $0.downloadProgress != nil }),
               let progress = downloading.downloadProgress {
                CalmProgressBar(
                    value: progress,
                    title: "Downloading \(downloading.size.displayName)",
                    detail: "\(Int(progress * 100))%"
                )
            }

            if appState.appStatus == .idle, let combo = appState.shortcut(for: .commandMode) {
                Text("Select text and press \(CalmKeyCaps.compactText(for: combo)) to edit it with your voice")
                    .font(CalmFont.note)
                    .foregroundStyle(CalmColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let unloadMessage = appState.modelUnloadStatusMessage,
               appState.appStatus == .idle || appState.isAutoPaused {
                VStack(alignment: .leading, spacing: 2) {
                    Text(unloadMessage)
                        .foregroundStyle(CalmColor.ink2)
                    if let freed = appState.approximateMemoryFreedMB {
                        Text(String(format: "About %.0f MB of process memory was released.", freed))
                            .foregroundStyle(CalmColor.muted)
                    }
                }
                .font(CalmFont.note)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let session = appState.commandModeSession {
                commandSessionCard(session)
            }

            if appState.appStatus == .recording {
                CalmMicLevelMeter(meter: appState.audioMeter, barCount: 24)
                ObservedLiveTranscriptView(state: appState.liveTranscriptState)
                    .foregroundStyle(CalmColor.ink)
            }

            // The last error stays, with its fix, until dismissed.
            if let notice = appState.errorNotice,
               appState.appStatus == .idle || appState.appStatus == .error {
                errorNoticeCard(notice)
            }
        }
    }

    private var statusText: String {
        if let session = appState.commandModeSession {
            switch (appState.appStatus, session.phase) {
            case (.recording, _): return "Command Mode — listening"
            case (_, .rewriting): return "Rewriting selection…"
            default: return "Transcribing instruction…"
            }
        }
        if appState.isAutoPaused {
            return appState.autoPauseTriggerDisplayName.map { "Paused (\($0))" } ?? "Auto-paused"
        }
        switch appState.appStatus {
        case .idle:       return appState.dictationReadinessTitle
        case .recording:  return "Listening…"
        case .processing: return appState.processingStatusText
        case .error:
            // The card below shows the whole message once.
            return appState.errorNotice == nil ? appState.errorMessage ?? "Error" : "Something went wrong"
        }
    }

    private var statusColor: Color {
        if appState.commandModeSession != nil { return CalmColor.violet }
        if appState.isAutoPaused { return CalmColor.off }
        switch appState.appStatus {
        case .idle:       return appState.isDictationReady ? CalmColor.accent : CalmColor.amber
        case .recording:  return CalmColor.accent
        case .processing: return CalmColor.ink2
        case .error:      return CalmColor.amber
        }
    }

    private func errorNoticeCard(_ notice: DictationErrorNotice) -> some View {
        MenuNoticeCard(tone: .warning) {
            Text(notice.message)
                .font(CalmFont.note)
                .foregroundStyle(CalmColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                if let action = notice.action {
                    Button(action.title) {
                        appState.performErrorFix(action) { page in
                            settingsManager.open(appState: appState, page: page)
                        }
                    }
                    .calmButton(.primary, size: .small)
                }
                Button("Dismiss") { appState.dismissErrorNotice() }
                    .calmButton(.secondary, size: .small)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error")
    }

    /// Shown while Command Mode listens or rewrites: what is being edited,
    /// where, and how to back out.
    private func commandSessionCard(_ session: CommandModeSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                CalmIcon(.commands, size: 14)
                    .foregroundStyle(CalmColor.violet)
                Text(commandSessionTitle(session))
                    .font(CalmFont.sf(13, weight: 560))
                    .foregroundStyle(CalmColor.ink)
            }
            if session.phase == .rewriting, let instruction = session.instruction, !instruction.isEmpty {
                Text("“\(instruction)”").lineLimit(2).foregroundStyle(CalmColor.ink2)
            }
            if session.phase == .rewriting, let written = session.previewTail {
                Text(written).lineLimit(2).foregroundStyle(CalmColor.ink2)
            }
            if session.kind != .compose {
                Text("\(session.kind == .answer ? "About" : "Editing") “\(session.selectionPreview)”")
                    .lineLimit(2)
                    .foregroundStyle(CalmColor.muted)
            }
            Text(commandSessionDetail(session))
                .foregroundStyle(CalmColor.muted)
        }
        .font(CalmFont.note)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CommandReviewView.violetSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func commandSessionTitle(_ session: CommandModeSession) -> String {
        switch (session.kind, session.phase) {
        case (.edit, .listening): return "Say how to change the selection"
        case (.compose, .listening): return "Say what to write"
        case (.answer, .listening): return "Ask about the selection"
        case (.edit, .rewriting): return "Rewriting with \(session.engineName)"
        case (.compose, .rewriting): return "Writing with \(session.engineName)"
        case (.answer, .rewriting): return "Answering with \(session.engineName)"
        }
    }

    private func commandSessionDetail(_ session: CommandModeSession) -> String {
        guard session.kind != .compose else {
            let place = session.appName.flatMap { $0.isEmpty ? nil : "Typed at the cursor in \($0)" } ?? "Typed at the cursor"
            return "\(place) · Esc cancels"
        }
        var parts = ["\(session.characterCount) characters"]
        if let app = session.appName, !app.isEmpty { parts[0] += " in \(app)" }
        parts.append(session.kind == .answer ? "Esc cancels" : "Esc leaves it unchanged")
        return parts.joined(separator: " · ")
    }

    // MARK: - Notices and choices

    private var supplementaryContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let info = appState.updateChecker.activeUpdateInfo {
                MenuNoticeCard(tone: .success) {
                    Text("VocaMac \(info.tagName) is ready")
                        .font(CalmFont.sf(13, weight: 600))
                        .foregroundStyle(CalmColor.ink)
                    Button("See what’s new") { updateWindowManager.open(appState: appState, info: info) }
                        .calmButton(.primary, size: .small)
                }
                .accessibilityElement(children: .contain)
            }

            // Setup problems come first: nothing else works until they are fixed.
            if needsSetup {
                permissionsSection
            }

            if let crash = appState.pendingCrashReport {
                crashSection(crash)
            }

            // A dictation that failed or was interrupted, with its audio saved
            if let entry = appState.recoverableHistoryEntry {
                recoverySection(entry)
            }

            // A spelling the user fixed, offered for the dictionary
            if let suggestion = appState.dictionarySuggestions.first {
                suggestionSection(suggestion)
            }

            if let held = appState.heldOutput {
                heldOutputSection(held)
            }

            // Microphone and writing style for the next dictation
            recordingOptionsSection

            // Last Command Mode edit, which replaces the dictation card until
            // the next dictation so its original stays one click away.
            if let edit = appState.lastCommandEdit {
                MenuSeparator()
                commandEditSection(edit)
            } else if let transcription = appState.lastTranscription {
                MenuSeparator()
                transcriptionSection(transcription, output: appState.lastOutput)
            }
        }
        .padding(.top, 2)
    }

    private func heldOutputSection(_ held: String) -> some View {
        MenuNoticeCard(tone: .neutral) {
            HStack {
                Text("Saved dictation")
                    .font(CalmFont.sf(13, weight: 600))
                    .foregroundStyle(CalmColor.ink)
                Spacer()
                MenuIconButton(icon: .copy, help: "Copy saved dictation") { appState.copyHeldOutput() }
            }
            Text("The destination changed before it could be typed.")
                .font(CalmFont.note)
                .foregroundStyle(CalmColor.muted)
            Text(held)
                .font(.system(size: 13))
                .foregroundStyle(CalmColor.ink)
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Recording Options

    /// Microphone and writing style as value rows, like a menu's submenus.
    private var recordingOptionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            microphoneRow

            if appState.writingStyleEnabled {
                writingStyleRow
                // Only shown while a one-off override is waiting, so it can
                // be seen and cancelled.
                if appState.nextWritingProfile != nil {
                    nextDictationRow
                }
            }

            NextDictationSummary()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

            if let notice = recordingOptionsNotice {
                notice
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }

    /// The one line of follow-up the rows above need, if any.
    private var recordingOptionsNotice: AnyView? {
        if let fallbackNotice = appState.inputDeviceFallbackNotice {
            return AnyView(CalmInlineNotice(fallbackNotice, tone: .warning))
        }
        if appState.isSecureInputActive, appState.hotKeyIsKeyed {
            return AnyView(CalmInlineNotice(
                "Secure keyboard entry is on in another app. Your shortcut still works through a fallback.",
                tone: .info
            ))
        }
        if appState.isRecording {
            return AnyView(Text("Stop recording before changing the microphone.")
                .font(CalmFont.note).foregroundStyle(CalmColor.muted))
        }
        if let bindNotice {
            return AnyView(CalmInlineNotice(bindNotice, tone: .success))
        }
        return nil
    }

    /// A pending one-off override, with a way to cancel it. Choosing one lives
    /// in the Style menu, so this row only exists while one is waiting.
    private var nextDictationRow: some View {
        MenuValueRow(title: "Next dictation only") {
            HStack(spacing: 6) {
                Text(appState.nextWritingProfile.map(nextProfileLabel) ?? "")
                    .font(CalmFont.note)
                    .foregroundStyle(CalmColor.muted)
                MenuIconButton(icon: .close, help: "Cancel and use the app's usual style") {
                    appState.nextWritingProfile = nil
                }
            }
        }
    }

    /// Which style dictation into the app in front will use. Picking a style
    /// remembers it for that app; the submenu applies one just once.
    private var writingStyleRow: some View {
        let appName = appState.activeWritingTargetName
        return MenuValueRow(title: appName.map { "Style in \($0)" } ?? "Style") {
            Menu {
                Section(appName.map { "Always use in \($0)" } ?? "Always use") {
                    ForEach(WritingStyle.allCases) { style in
                        VocaMenuChoice(
                            title: style.displayName,
                            isSelected: style == appState.activeWritingStyle.style
                        ) {
                            bindNotice = appState.bindFrontmostApp(to: style)
                                .map { "\(style.displayName) style saved for \($0)" }
                        }
                    }
                }

                if appState.activeWritingStyle.matchedAppName != nil {
                    Button("Use My Default Style (\(appState.writingStyleDefault.displayName))") {
                        bindNotice = appState.unbindFrontmostApp()
                            .map { "\($0) now uses your default style" }
                    }
                }

                Divider()

                // One-offs are a different act from "always", so they get their
                // own labelled group instead of hiding two levels down.
                Section("Only for the Next Dictation") {
                    Button("Exactly as Transcribed") { appState.useRawForNextDictation() }
                    Menu("Style…") {
                        ForEach(WritingStyle.allCases) { style in
                            Button(style.displayName) { appState.useNextWritingFormat(style) }
                        }
                    }
                    if appState.writingRewriteEnabled {
                        Menu("Tone…") {
                            ForEach(WritingIntent.allCases) { intent in
                                Button(intent.displayName) { appState.useNextWritingIntent(intent) }
                            }
                        }
                    }
                }

                Divider()

                Button("Writing Style Settings…") {
                    settingsManager.open(appState: appState, page: .writingStyles)
                }
            } label: {
                Text(writingStyleLabel)
            }
            .menuValueStyle()
            .help("How text is formatted when you dictate into this app")
        }
    }

    private var writingStyleLabel: String {
        let resolved = appState.activeWritingStyle
        var style = resolved.style.displayName
        if appState.writingRewriteEnabled,
           resolved.profile.allowsRewrite,
           resolved.intent != .preserve {
            style += " · \(resolved.intent.displayName)"
        }
        return style
    }

    private func nextProfileLabel(_ profile: WritingProfile) -> String {
        guard profile.cleanup != .raw else { return "Exactly as transcribed" }
        guard appState.writingRewriteEnabled,
              profile.format.supportsWording,
              profile.intent != .preserve,
              profile.cleanup == .inherit else {
            return profile.format.displayName
        }
        return "\(profile.format.displayName) · \(profile.intent.displayName)"
    }

    // MARK: - Microphone

    /// Provides a quick microphone switcher without requiring the Settings window.
    /// The selected device is persisted by AppState and takes effect on the next
    /// recording; it does not change macOS's global input-device selection.
    private var microphoneRow: some View {
        MenuValueRow(title: "Microphone") {
            Menu {
                VocaMenuChoice(title: "System Default", isSelected: appState.selectedAudioDeviceID.isEmpty) {
                    appState.selectAudioDevice(nil)
                }

                if selectedAudioDeviceIsUnavailable {
                    Divider()
                    Text(selectedAudioDeviceDisplayName)
                }

                if !audioDevices.isEmpty {
                    Divider()
                }

                ForEach(audioDevices) { device in
                    VocaMenuChoice(title: device.name, isSelected: appState.selectedAudioDeviceID == device.id) {
                        appState.selectAudioDevice(device)
                    }
                }

                if audioDevices.isEmpty {
                    Text("No audio input devices found")
                }

                Divider()
                Button("Refresh List") { refreshAudioDevices() }
            } label: {
                Text(selectedAudioDeviceDisplayName)
            }
            .menuValueStyle()
            .disabled(appState.isRecording)
            .help("Applies to the next recording. Does not change macOS's system default.")
        }
        .onAppear {
            refreshAudioDevices()
        }
        .onReceive(NotificationCenter.default.publisher(for: .vocaAudioDevicesChanged)) { _ in
            refreshAudioDevices()
        }
    }

    private var selectedAudioDevice: AudioDevice? {
        guard !appState.selectedAudioDeviceID.isEmpty else { return nil }
        return audioDevices.first { $0.id == appState.selectedAudioDeviceID }
    }

    private var selectedAudioDeviceIsUnavailable: Bool {
        !appState.selectedAudioDeviceID.isEmpty && selectedAudioDevice == nil
    }

    private var selectedAudioDeviceDisplayName: String {
        if appState.selectedAudioDeviceID.isEmpty {
            return "System Default"
        }
        if let selectedAudioDevice {
            return selectedAudioDevice.name
        }
        let storedName = appState.selectedAudioDeviceName.isEmpty
            ? "Selected microphone"
            : appState.selectedAudioDeviceName
        return "\(storedName) (Unavailable)"
    }

    private func refreshAudioDevices() {
        audioDevices = AudioEngine.availableInputDevices()
        if let selectedAudioDevice {
            appState.selectedAudioDeviceName = selectedAudioDevice.name
        }
    }

    // MARK: - Last Dictation

    private func transcriptionSection(
        _ result: VocaTranscription,
        output: DictationOutputResult?
    ) -> some View {
        // Other workflows (for example Command Mode and history retry) can
        // update lastOutput without producing a new lastTranscription. Only
        // pair an output with the raw transcript it was actually derived from.
        let matchingOutput = output?.original == result.text ? output : nil
        let displayedText = matchingOutput?.text ?? result.text
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Last dictation")
                    .calmType(.caption)
                Spacer()
                MenuIconButton(icon: .copy, help: "Copy to clipboard") {
                    copyToPasteboard(displayedText)
                }
            }

            Text(displayedText)
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .foregroundStyle(CalmColor.ink)
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let matchingOutput {
                Text(matchingOutput.summary)
                    .font(CalmFont.note)
                    .foregroundStyle(CalmColor.muted)
            }

            Text([
                "\(String(format: "%.1f", result.audioLengthSeconds))s audio",
                "\(String(format: "%.1f", result.duration))s to transcribe",
                result.detectedLanguage.uppercased(),
            ].joined(separator: " · "))
            .font(CalmFont.note)
            .monospacedDigit()
            .foregroundStyle(CalmColor.muted)
        }
        .padding(EdgeInsets(top: 4, leading: 10, bottom: 6, trailing: 6))
    }

    private func commandEditSection(_ edit: CommandModeEdit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                CalmIcon(.commands, size: 13).foregroundStyle(CalmColor.violet)
                Text(commandEditTitle(edit))
                    .calmType(.caption)
                Spacer()
                Text(edit.engineName)
                    .font(CalmFont.note)
                    .foregroundStyle(CalmColor.muted)
                    .lineLimit(1)
            }
            Text("“\(edit.instruction)”")
                .font(CalmFont.note)
                .foregroundStyle(CalmColor.muted)
                .lineLimit(2)
            Text(edit.replacement.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: 13.5))
                .foregroundStyle(CalmColor.ink)
                .lineLimit(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let note = edit.note {
                CalmInlineNotice("Check this: \(note).", tone: .warning)
            }
            if edit.kind != .action {
                HStack(spacing: 8) {
                    if edit.kind == .edit {
                        Button("Copy Original") { copyToPasteboard(edit.original) }
                            .calmButton(.secondary, size: .small)
                            .help("Copy the text as it was before the edit")
                    }
                    Button("Copy Result") { copyToPasteboard(edit.replacement) }
                        .calmButton(.secondary, size: .small)
                }
            }
        }
        .padding(EdgeInsets(top: 4, leading: 10, bottom: 6, trailing: 10))
    }

    private func commandEditTitle(_ edit: CommandModeEdit) -> String {
        switch edit.kind {
        case .edit: return "Last Edit"
        case .composed: return "Last Written"
        case .answer: return "Last Answer"
        case .action: return "Last Action"
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Permissions

    private var allPermissionsGranted: Bool {
        appState.micPermission == .granted
            && appState.accessibilityPermission == .granted
            && appState.inputMonitoringPermission == .granted
    }

    private var needsSetup: Bool {
        !allPermissionsGranted || appState.needsSpeechModel || appState.permissionsMayNeedRelaunch
    }

    private var permissionsSection: some View {
        MenuNoticeCard(tone: .warning) {
            HStack(spacing: 6) {
                CalmIcon(.warning, size: 14, weight: 2).foregroundStyle(CalmColor.amber)
                Text("Finish setting up")
                    .font(CalmFont.sf(13, weight: 600))
                    .foregroundStyle(CalmColor.ink)
            }

            if appState.needsSpeechModel {
                permissionRow(
                    title: "Speech model",
                    detail: "Pick a model so VocaMac can transcribe.",
                    isDenied: false,
                    buttonTitle: "Choose…",
                    help: "Open Speech Model settings",
                    action: { settingsManager.open(appState: appState, page: .speechModel) }
                )
            }

            if appState.micPermission != .granted {
                permissionRow(
                    title: "Microphone",
                    detail: appState.micPermission == .denied
                        ? "Denied. Turn it on in Privacy & Security."
                        : "Captures your voice for transcription.",
                    isDenied: appState.micPermission == .denied,
                    action: { appState.requestMicrophonePermission() }
                )
            }

            if appState.accessibilityPermission != .granted {
                permissionRow(
                    title: "Accessibility",
                    detail: "Needed for global hotkeys and typing text.",
                    isDenied: appState.accessibilityPermission == .denied,
                    action: { appState.requestAccessibilityPermission() }
                )
            }

            if appState.inputMonitoringPermission != .granted {
                permissionRow(
                    title: "Input Monitoring",
                    detail: "Needed to detect the hotkey in every app.",
                    isDenied: appState.inputMonitoringPermission == .denied,
                    action: { appState.requestInputMonitoringPermission() }
                )
            }

            if appState.permissionsMayNeedRelaunch {
                permissionRow(
                    title: appState.permissionsAwaitingGrant ? "Still shows as off?" : "Shortcut not connected",
                    detail: appState.permissionsAwaitingGrant
                        ? "macOS can wait to apply a permission until VocaMac reopens."
                        : "macOS hasn't connected your shortcut yet. Reopening fixes this.",
                    isDenied: false,
                    buttonTitle: "Reopen",
                    help: "Quit and reopen VocaMac",
                    action: { appState.relaunch() }
                )
            }
        }
    }

    /// A missing permission with its reason and one button to fix it.
    private func permissionRow(
        title: String,
        detail: String,
        isDenied: Bool,
        buttonTitle: String? = nil,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(CalmFont.sf(13, weight: 560))
                    .foregroundStyle(CalmColor.ink)
                Text(detail)
                    .font(CalmFont.note)
                    .foregroundStyle(isDenied ? CalmColor.amber : CalmColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(buttonTitle ?? (isDenied ? "Open…" : "Allow…"), action: action)
                .calmButton(.primary, size: .small)
                .help(help ?? (isDenied ? "Open System Settings" : "Ask macOS for access"))
        }
    }

    // MARK: - Recovery and Suggestions

    private func recoverySection(_ entry: DictationHistoryEntry) -> some View {
        MenuNoticeCard(tone: .warning) {
            Text(recoveryTitle(entry))
                .font(CalmFont.sf(13, weight: 600))
                .foregroundStyle(CalmColor.ink)
            Text("The \(String(format: "%.0f", entry.audioSeconds))-second recording is saved. Retry transcribes it again and copies the text\(pasteShortcutHint).")
                .font(CalmFont.note)
                .foregroundStyle(CalmColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if appState.retryingHistoryEntryID == entry.id {
                    CalmSpinner(size: 15)
                    Text("Transcribing…").font(CalmFont.note).foregroundStyle(CalmColor.muted)
                } else {
                    Button("Retry") {
                        Task { await appState.retryHistoryEntry(entry.id) }
                    }
                    .calmButton(.primary, size: .small)
                    .disabled(appState.retryingHistoryEntryID != nil)
                }
                Button("Dismiss") { appState.dismissRecovery(entry.id) }
                    .calmButton(.secondary, size: .small)
                Spacer(minLength: 4)
                Button("History") { openHistory() }
                    .calmLink(muted: true, font: CalmFont.note)
            }
        }
    }

    private func crashSection(_ crash: PendingCrashReport) -> some View {
        MenuNoticeCard(tone: .warning) {
            Text("VocaMac quit unexpectedly last time")
                .font(CalmFont.sf(13, weight: 600))
                .foregroundStyle(CalmColor.ink)
            Text("Report opens a new GitHub issue in your browser, filled in with where it crashed. Opening it gives those details to GitHub; nothing is posted until you submit.")
                .font(CalmFont.note)
                .foregroundStyle(CalmColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Report…") { appState.reportPendingCrash() }
                    .calmButton(.primary, size: .small)
                    .disabled(!appState.canReportPendingCrash)
                    .help(appState.canReportPendingCrash ? "" : "Available when the dictation finishes")
                Button("Dismiss") { appState.dismissPendingCrash() }
                    .calmButton(.secondary, size: .small)
                Spacer(minLength: 4)
                Button("Show File") { appState.revealPendingCrashReport() }
                    .calmLink(muted: true, font: CalmFont.note)
                    .help(crash.fileURL.lastPathComponent)
            }
        }
    }

    private func recoveryTitle(_ entry: DictationHistoryEntry) -> String {
        switch entry.status {
        case .interrupted: return "Your last dictation was interrupted"
        case .cancelled: return "Your last dictation was cancelled"
        default: return "Your last dictation failed"
        }
    }

    private var pasteShortcutHint: String {
        guard let combo = appState.shortcut(for: .pasteLastDictation) else { return "" }
        return " — then press \(KeyCodeReference.displayName(for: combo)) to paste it"
    }

    private func suggestionSection(_ suggestion: CorrectionSuggestion) -> some View {
        MenuNoticeCard(tone: .neutral) {
            HStack(spacing: 8) {
                (Text("Spell it ") + Text(suggestion.corrected).fontWeight(.semibold) + Text(" next time?"))
                    .font(.system(size: 13))
                    .foregroundStyle(CalmColor.ink)
                    .lineLimit(2)
                Spacer(minLength: 6)
                Button("Add") { appState.acceptDictionarySuggestion(suggestion) }
                    .calmButton(.secondary, size: .small)
                MenuIconButton(icon: .close, help: "Dismiss suggestion") {
                    appState.dismissDictionarySuggestion(suggestion)
                }
            }
        }
    }

    private func openHistory() {
        settingsManager.open(appState: appState, page: .history)
    }

    // MARK: - Actions

    /// The design's first group: start (or finish) a dictation, paste the
    /// last one, Smart Cleanup on or off.
    private var primaryRows: some View {
        VStack(spacing: 0) {
            dictationRows
            menuRow(
                "Paste last dictation",
                shortcut: appState.shortcut(for: .pasteLastDictation).map { CalmKeyCaps.compactText(for: $0) }
            ) {
                // The panel has to give focus back before the text is typed.
                panelWindow.window?.orderOut(nil)
                Task { @MainActor in
                    await Task.yield()
                    appState.pasteLastDictation()
                }
            }
            .disabled(appState.lastDictationText == nil || appState.isRecording || appState.appStatus == .processing)
            menuRow("Smart Cleanup", isChecked: appState.transcriptCleanupEnabled) {
                appState.transcriptCleanupEnabled.toggle()
                Task { @MainActor in await appState.syncTranscriptCleanup() }
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 0) {
            menuRow("Scratchpad") { scratchpadManager.open(appState: appState) }
                .help("A floating note to dictate into")
            menuRow("Transcribe a file…") { fileTranscriptionManager.open(appState: appState) }
                .help("Transcribe an audio or video file")
            menuRow("Transcribe system audio…") { meetingCaptureManager.open(appState: appState) }
                .help("Transcribe what this Mac is playing")

            MenuSeparator()

            menuRow("Open VocaMac") { settingsManager.open(appState: appState) }
            menuRow("History") { openHistory() }
            // The same switch as "Save history" in Settings, one click away
            // for a private moment.
            menuRow(appState.historyEnabled ? "Pause history" : "Resume history") {
                // Said explicitly so this open menu redraws its own label.
                appState.objectWillChange.send()
                appState.historyEnabled.toggle()
            }
            menuRow("Settings…", shortcut: "⌘,", keyEquivalent: ",") {
                settingsManager.open(appState: appState, page: .dictation)
            }
            menuRow("Check for updates…") {
                settingsManager.open(appState: appState, page: .about)
                Task { await appState.updateChecker.checkForUpdates() }
            }
            if gateway.status.allowsPairing {
                menuRow("Pair phone…") {
                    settingsManager.open(appState: appState, page: .gateway, showPairing: true)
                }
            }

            MenuSeparator()

            menuRow("Quit VocaMac", shortcut: "⌘Q", keyEquivalent: "q") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    /// Start, or while a dictation runs, finish or cancel it.
    @ViewBuilder
    private var dictationRows: some View {
        let isEdit = appState.commandModeSession != nil
        switch appState.appStatus {
        case .recording:
            menuRow(isEdit ? "Finish instruction" : "Stop and type") {
                Task { @MainActor in await appState.stopRecordingAndTranscribe() }
            }
            cancelRow(isEdit: isEdit)
        case .processing:
            if appState.canCancelDictation {
                cancelRow(isEdit: isEdit)
            }
        case .idle, .error:
            menuRow("Start dictation", shortcut: dictationKeyName) {
                // The panel gives focus back to the app the words are for.
                panelWindow.window?.orderOut(nil)
                Task { @MainActor in
                    await Task.yield()
                    await appState.toggleHandsFreeDictation()
                }
            }
            .help("Records until you press the hands-free shortcut, click Stop on the overlay, or stop talking")
        }
    }

    /// Throws the dictation away, as Escape does. Offered for every
    /// dictation, not only Command Mode edits.
    private func cancelRow(isEdit: Bool) -> some View {
        menuRow(isEdit ? "Cancel edit" : "Cancel dictation", shortcut: appState.escapeCancelsDictation ? "Esc" : nil) {
            Task { @MainActor in await appState.cancelDictation() }
        }
        .help(isEdit ? "Leave the selection unchanged" : "Discard this dictation")
    }

    private var dictationKeyName: String {
        CalmKeyCaps.compactText(for: HotKeyCombo(keyCode: appState.hotKeyCode, modifiers: appState.hotKeyModifiers))
    }

    /// A row that highlights like a native menu item. With a `keyEquivalent`,
    /// ⌘ plus that key triggers the row while the menu is open, so the
    /// shortcut it shows actually works.
    @ViewBuilder
    private func menuRow(
        _ title: String,
        shortcut: String? = nil,
        isChecked: Bool? = nil,
        keyEquivalent: KeyEquivalent? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let row = Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(CalmColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isChecked == true {
                    CalmIcon(.check, size: 13, weight: 2)
                        .foregroundStyle(CalmColor.muted)
                } else if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12.5))
                        .foregroundStyle(CalmColor.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: MenuPanelMetrics.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .accessibilityAddTraits(isChecked == true ? .isSelected : [])
        if let keyEquivalent {
            row.keyboardShortcut(keyEquivalent, modifiers: .command)
        } else {
            row
        }
    }
}

// MARK: - Menu Row Button Style

/// A menu item: no fill until hovered, then panel2 at radius 6, like a
/// native menu highlight.
struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRowBody(configuration: configuration)
    }

    private struct MenuRowBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.calmPreviewInteraction) private var forced
        @State private var isHovered = false

        var body: some View {
            let highlighted = (isHovered || forced == .hover) && isEnabled
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: CalmMetrics.Radius.menuItem, style: .continuous)
                        .fill(configuration.isPressed ? CalmColor.line2 : highlighted ? CalmColor.panel2 : .clear)
                )
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { isHovered = $0 }
        }
    }
}

// MARK: - Menu Panel Components

enum MenuPanelMetrics {
    /// The design's menu is 280 wide.
    static let width: CGFloat = 280
    /// Corner of the panel itself: the menu's radius.
    static let panelRadius: CGFloat = CalmMetrics.Radius.menu
    /// Room between the panel edge and its rows.
    static let padding: CGFloat = 5
    static let rowHeight: CGFloat = 30
}

/// Weak reference used to dismiss the panel before pasting into its destination.
private final class MenuPanelWindowReference {
    weak var window: NSWindow?
}

/// Keeps the MenuBarExtra window exactly as tall as the panel.
///
/// `.menuBarExtraStyle(.window)` does not follow later height changes. Resize
/// the window pinned to its top edge and rebuild the shadow for the new shape.
private struct MenuPanelWindowSizer: NSViewRepresentable {
    let height: CGFloat
    var onWindow: ((NSWindow?) -> Void)?

    func makeNSView(context: Context) -> SizerView {
        let view = SizerView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ view: SizerView, context: Context) {
        view.targetHeight = height
        view.onWindow = onWindow
    }

    final class SizerView: NSView {
        var onWindow: ((NSWindow?) -> Void)?
        var targetHeight: CGFloat = 0 {
            didSet { if abs(targetHeight - oldValue) > 0.5 { scheduleResize() } }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { Self.makePlainPanel(window) }
            onWindow?(window)
            scheduleResize()
        }

        /// The panel paints its own rounded menu surface. Left alone, the
        /// system window draws its material and a light rim around it, and
        /// the surface sat inside that as a second frame. Clearing the window
        /// and hiding the material leaves one edge: the panel's own hairline,
        /// with the window shadow following its shape.
        static func makePlainPanel(_ window: NSWindow) {
            window.isOpaque = false
            window.backgroundColor = .clear
            if let frameView = window.contentView?.superview {
                hideSystemMaterial(in: frameView)
            }
            window.invalidateShadow()
        }

        private static func hideSystemMaterial(in view: NSView) {
            for subview in view.subviews {
                // NSVisualEffectView, and the glass view newer systems use.
                if subview is NSVisualEffectView || String(describing: type(of: subview)).contains("GlassEffect") {
                    subview.isHidden = true
                }
                hideSystemMaterial(in: subview)
            }
        }

        private func scheduleResize() {
            // Resizing inside SwiftUI's layout pass re-enters it; wait a turn.
            DispatchQueue.main.async { [weak self] in self?.resizeWindow() }
        }

        private func resizeWindow() {
            guard let window, targetHeight > 1 else { return }
            let current = window.frame
            let contentRect = window.contentRect(forFrameRect: current)
            let desired = window.frameRect(forContentRect: NSRect(
                x: contentRect.minX,
                y: contentRect.maxY - targetHeight,
                width: contentRect.width,
                height: targetHeight
            ))
            guard abs(desired.height - current.height) > 0.5 else { return }
            window.setFrame(desired, display: true)
            window.invalidateShadow()
        }
    }
}

private struct MenuContentHeightKey: SwiftUI.PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Summed across the pinned top and bottom of the panel.
private struct MenuChromeHeightKey: SwiftUI.PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value += nextValue() }
}

private extension View {
    func measureHeight<Key: SwiftUI.PreferenceKey>(_ key: Key.Type) -> some View where Key.Value == CGFloat {
        background(GeometryReader { proxy in
            Color.clear.preference(key: key, value: proxy.size.height)
        })
    }

    /// A pull-down showing its current value at the trailing edge of a row,
    /// in the muted colour of a menu item's shortcut.
    func menuValueStyle() -> some View {
        self
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .fixedSize()
            .foregroundStyle(CalmColor.muted)
            .tint(CalmColor.muted)
            .font(.system(size: 12.5))
    }
}

/// The menu's separator: a 1-point line inset 6, with 5 above and below.
private struct MenuSeparator: View {
    var body: some View {
        Rectangle()
            .fill(CalmColor.line)
            .frame(height: 1)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .accessibilityHidden(true)
    }
}

/// A menu row with a title and a value control on the right (Microphone,
/// Style), the height of a menu item.
private struct MenuValueRow<Accessory: View>: View {
    let title: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(CalmColor.ink)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 10)
            accessory
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(minHeight: MenuPanelMetrics.rowHeight)
    }
}

/// A notice inside the menu: a panel-coloured block (amber-tinted for
/// problems) with a title, a line or two, and small buttons.
private struct MenuNoticeCard<Content: View>: View {
    var tone: CalmTone = .neutral
    @ViewBuilder let content: Content

    private var fill: Color {
        switch tone {
        case .warning: return CalmColor.amberSoft
        case .success: return CalmColor.accentSoft
        case .neutral, .info, .label: return CalmColor.panel
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The status line's dot: 7 points with a 3-point soft ring, pulsing while
/// a dictation runs.
private struct MenuStatusDot: View {
    let color: Color
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.16))
                .frame(width: 13, height: 13)
                .scaleEffect(isActive && pulse ? 1.3 : 1)
                .opacity(isActive && pulse ? 0.4 : 1)
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
        .frame(width: 13, height: 13)
        .onAppear { startPulse() }
        .onChange(of: isActive) { startPulse() }
        .accessibilityHidden(true)
    }

    private func startPulse() {
        guard isActive, !reduceMotion else {
            pulse = false
            return
        }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            pulse = true
        }
    }
}

/// A small borderless icon button with a hover highlight.
private struct MenuIconButton: View {
    let icon: CalmIconName
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CalmIcon(icon, size: 13)
                .foregroundStyle(CalmColor.muted)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(MenuRowButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Audio Level View

/// A simple horizontal bar that visualizes the current audio input level
struct AudioLevelView: View {
    let level: Float

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.2))

                // Level indicator
                RoundedRectangle(cornerRadius: 2)
                    .fill(levelColor)
                    .frame(width: max(0, geometry.size.width * CGFloat(level)))
                    .animation(.easeOut(duration: 0.1), value: level)
            }
        }
    }

    /// Petrol while the level is comfortable, amber when loud, clay when
    /// it is close to clipping.
    private var levelColor: Color {
        if level > 0.8 { return VocaDesign.clay }
        if level > 0.5 { return VocaDesign.warning }
        return VocaDesign.accent
    }
}
