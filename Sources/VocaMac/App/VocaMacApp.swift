// VocaMacApp.swift
// VocaMac
//
// Main entry point for the VocaMac application.
// Configures the app as a menu bar-only application (no Dock icon).

import SwiftUI

extension Notification.Name {
    static let vocaOpenURL = Notification.Name("com.vocamac.open-url")
    static let showOnboarding = Notification.Name("com.vocamac.showOnboarding")
}

final class VocaApplicationDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NotificationCenter.default.post(name: .vocaOpenURL, object: url)
        }
    }
}

/// Manages VocaMac's main window (sidebar pages and the Settings sheet)
/// for a menu-bar-only app.
@MainActor
final class SettingsWindowManager: ObservableObject {
    /// Shared instance. The deep-link observer in `VocaMacApp.init` reads
    /// this manager before its `@StateObject` is installed on a view, and
    /// every such access builds a new manager that is released as soon as
    /// the call returns — so a link would open a second window instead of
    /// focusing the open one, and the close observer token would die with
    /// the manager, leaving the Dock icon behind.
    static let shared = SettingsWindowManager()

    private var settingsWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?

    /// Page to show when the window appears, in the `SettingsPage`
    /// vocabulary (mapped to a sidebar page or a Settings sheet page by
    /// `CalmNavigation`). Survives first-open timing. The window also honors
    /// `AppState.requestedSettingsPage`.
    @Published private(set) var requestedPage: SettingsPage?

    /// Pair-phone sheet to present when Gateway settings appears.
    @Published private(set) var pendingPairingPresentation = false

    func open(appState: AppState, page: SettingsPage? = nil, showPairing: Bool = false) {
        if let target = page ?? (showPairing ? SettingsPage.gateway : nil) {
            recordOpenRequest(page: target, showPairing: showPairing)
            appState.requestSettingsPage(target)
        }

        // If window already exists, just bring it to front
        if let window = settingsWindow {
            restoreUsableFrame(window)
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // The v3 window: sidebar pages, with Settings as a sheet inside it.
        let windowView = CalmWindowView()
            .environmentObject(appState)
            .environmentObject(self)
        let defaultSize = SettingsWindowGeometry.defaultContentSize

        // Create a new window
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "VocaMac"
        // Content runs up under a transparent title bar, so the frame-coloured
        // sidebar reaches the top edge with the traffic lights sitting in it.
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = CalmNSColor.frame
        let hostingController = NSHostingController(rootView: windowView)
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        // The Settings sheet (1000 × 680) must fit inside the smallest window.
        window.contentMinSize = SettingsWindowGeometry.minimumContentSize
        // With automatic hosting sizing disabled, attaching the controller
        // can collapse the initial window to its 1-point intrinsic width.
        // Establish the default again before applying a saved frame.
        window.setContentSize(defaultSize)
        window.autorecalculatesKeyViewLoop = true
        if !window.setFrameUsingName("VocaMac.Settings") { window.center() }
        restoreUsableFrame(window)
        window.setFrameAutosaveName("VocaMac.Settings")
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.settingsWindow = window

        // Show in the Dock so the window can take focus.
        DockVisibilityCoordinator.shared.windowDidOpen()
        NSApp.activate(ignoringOtherApps: true)

        // Held so it can be removed on close — a block-based observer lives
        // until its token is released, so opening repeatedly would otherwise
        // stack up observers.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.settingsWindow = nil
                if let observer = self.closeObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.closeObserver = nil
                }
                DockVisibilityCoordinator.shared.windowDidClose()
            }
        }
    }

    /// Stores a sidebar page and/or pair-phone request until Settings consumes it.
    func recordOpenRequest(page: SettingsPage? = nil, showPairing: Bool = false) {
        if let page {
            requestedPage = page
        }
        if showPairing {
            pendingPairingPresentation = true
            if requestedPage == nil {
                requestedPage = .gateway
            }
        }
    }

    /// Returns and clears the requested sidebar page, if any.
    func consumeRequestedPage() -> SettingsPage? {
        guard let page = requestedPage else { return nil }
        requestedPage = nil
        return page
    }

    /// Consumes the pair-phone request only when the Gateway pane can show the sheet.
    /// Leaves the flag set otherwise so a later pairable/ready status can retry.
    func consumePendingPairingPresentation(canPresent: Bool) -> Bool {
        guard pendingPairingPresentation, canPresent else { return false }
        pendingPairingPresentation = false
        return true
    }

    /// Reject collapsed or off-screen frames left by hosting layout or an
    /// earlier display configuration before making the window visible.
    private func restoreUsableFrame(_ window: NSWindow) {
        let screens = NSScreen.screens.map(\.visibleFrame)
        if SettingsWindowGeometry.needsReset(window.frame, screens: screens) {
            window.setContentSize(SettingsWindowGeometry.defaultContentSize)
            window.center()
        }
    }
}

/// Manages the standalone update details window.
/// Update details open in their own window rather than as a sheet inside the
/// MenuBarExtra popover: sheets there detach, fight the popover for focus,
/// and pull it down along with themselves when dismissed.
@MainActor
final class UpdateWindowManager: ObservableObject {
    private var updateWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?

    /// The release currently on screen, so a newer one can replace it.
    private var presentedInfo: UpdateInfo?

    func open(appState: AppState, info: UpdateInfo) {
        if let window = updateWindow, window.isVisible {
            // Already showing this release — just bring it forward. If a
            // newer one arrived while the window was open, swap the contents
            // rather than leaving the stale release on screen.
            if presentedInfo != info {
                window.contentView = NSHostingView(rootView: detailView(appState: appState, info: info))
                presentedInfo = info
            }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let updateView = detailView(appState: appState, info: info)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "VocaMac Update"
        // The dawn scene runs up under a transparent title bar.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = VocaDesign.canvasNSColor
        window.contentView = NSHostingView(rootView: updateView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.updateWindow = window
        self.presentedInfo = info

        // Show in the Dock so the window can take focus.
        DockVisibilityCoordinator.shared.windowDidOpen()
        NSApp.activate(ignoringOtherApps: true)

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updateWindow = nil
                self.presentedInfo = nil
                if let observer = self.closeObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.closeObserver = nil
                }
                DockVisibilityCoordinator.shared.windowDidClose()
            }
        }
    }

    private func detailView(appState: AppState, info: UpdateInfo) -> some View {
        UpdateDetailView(info: info, isPresented: Binding(
            get: { true },
            set: { [weak self] stillPresented in
                if !stillPresented { self?.updateWindow?.close() }
            }
        ))
        .environmentObject(appState)
    }
}

/// Manages the onboarding window
@MainActor
final class OnboardingWindowManager: ObservableObject {
    /// Shared instance. Every caller lives in a closure created by
    /// `VocaMacApp.init`, where a `@StateObject` is not yet installed on a
    /// view: each access there builds a *new* manager that is released as soon
    /// as the call returns. A per-App-struct manager therefore forgets its own
    /// window the moment it is shown — nothing is left to bring an existing
    /// window forward, and the close observer token dies with it, so the Dock
    /// is never told the window went away.
    static let shared = OnboardingWindowManager()

    private var onboardingWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?

    private init() {}

    func open(appState: AppState) {
        // If window already exists, just bring it to front
        if let window = onboardingWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Create a new window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        // Create the onboarding view. It closes this window directly rather
        // than going back through the manager, so "Finish" and "Set up later"
        // work regardless of who still holds a reference to the manager.
        let onboardingView = OnboardingView(initialStep: appState.onboardingStartStep) { [weak window] in
            window?.close()
        }
            .environmentObject(appState)

        window.contentMinSize = NSSize(width: 880, height: 600)
        window.title = "Welcome to VocaMac"
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.contentView = NSHostingView(rootView: onboardingView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.onboardingWindow = window

        // Show in the Dock so the window can take focus.
        DockVisibilityCoordinator.shared.windowDidOpen()
        NSApp.activate(ignoringOtherApps: true)

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onboardingWindow = nil
                if let observer = self.closeObserver {
                    NotificationCenter.default.removeObserver(observer)
                    self.closeObserver = nil
                }
                DockVisibilityCoordinator.shared.windowDidClose()
            }
        }
    }
}

struct VocaMacApp: App {
    /// Set by the first `init`; see the URL observer there.
    @MainActor private static var didInstallURLObserver = false
    @NSApplicationDelegateAdaptor(VocaApplicationDelegate.self) private var applicationDelegate
    @StateObject private var appState = AppState.production()
    @StateObject private var settingsManager = SettingsWindowManager.shared
    @StateObject private var updateWindowManager = UpdateWindowManager()
    @StateObject private var fileTranscriptionManager = FileTranscriptionWindowManager.shared
    @StateObject private var scratchpadManager = ScratchpadWindowManager.shared
    @StateObject private var meetingCaptureManager = MeetingCaptureWindowManager()

    var body: some Scene {
        // Menu bar presence — the primary UI for VocaMac
        MenuBarExtra {
            MenuBarView(
                settingsManager: settingsManager,
                updateWindowManager: updateWindowManager,
                fileTranscriptionManager: fileTranscriptionManager,
                scratchpadManager: scratchpadManager,
                meetingCaptureManager: meetingCaptureManager
            )
                .environmentObject(appState)
        } label: {
            MenuBarIcon(
                appStatus: appState.appStatus,
                isCommandMode: appState.commandModeSession != nil,
                readiness: MenuBarReadiness(appState.dictationReadiness),
                accessibilityLabel: appState.menuBarAccessibilityLabel
            )
                .onAppear {
                    // Trigger startup from the SwiftUI lifecycle so it only runs
                    // on the AppState instance that SwiftUI actually retains.
                    // Previously, startup ran in AppState.init() which caused
                    // double initialization (and double event taps) because
                    // SwiftUI may instantiate the App struct more than once.
                    appState.triggerStartupIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)
    }

    @MainActor init() {
        // Ensure only one instance of VocaMac is running
        Self.ensureSingleInstance()
        appState.repairLegacyOnboardingCompletionIfNeeded()

        // For .app bundles, Dock hiding is handled by LSUIElement=true in Info.plist.
        // For direct binary execution, we set it programmatically.
        DispatchQueue.main.async {
            NSApp?.setActivationPolicy(.accessory)
        }

        // Listen for setup requests from Settings. Reopening setup must not
        // clear the durable completion flag: closing a refresher window should
        // never make onboarding appear again after the next login.
        NotificationCenter.default.addObserver(
            forName: .showOnboarding,
            object: nil,
            queue: .main
        ) { [self] _ in
            Task { @MainActor [self] in
                OnboardingWindowManager.shared.open(appState: self.appState)
            }
        }

        // SwiftUI can build the App struct more than once. A second observer
        // would handle every link twice — two confirmations, and a toggle
        // link that starts and immediately stops recording.
        if !Self.didInstallURLObserver {
            Self.didInstallURLObserver = true
            NotificationCenter.default.addObserver(
                forName: .vocaOpenURL,
                object: nil,
                queue: .main
            ) { [self] notification in
                guard let url = notification.object as? URL,
                      let link = VocaDeepLink(url: url) else { return }
                let returnTarget: NSRunningApplication?
                if link.requiresExternalConfirmation {
                    // Registered on the main queue, so this is the main actor.
                    let (target, allowed) = MainActor.assumeIsolated {
                        let target = Self.deepLinkReturnTarget(
                            lastActive: self.appState.frontmostAppResolver.lastActiveApplication()
                        )
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = "Allow VocaMac action?"
                        alert.informativeText = "Another app or website asked VocaMac to \(link.confirmationDescription). Continue only if you initiated this action."
                        alert.addButton(withTitle: "Allow")
                        alert.addButton(withTitle: "Cancel")
                        return (target, alert.runModal() == .alertFirstButtonReturn)
                    }
                    returnTarget = target
                    guard allowed else { return }
                } else {
                    returnTarget = nil
                }
                Task { @MainActor [self] in
                    // The confirmation window activates VocaMac. Put the user's
                    // original destination back in front before recording or text
                    // insertion resolves its target.
                    var isBackInFront = false
                    if let returnTarget {
                        isBackInFront = await Self.reactivate(returnTarget)
                    }
                    if link == .pasteLast, !DeepLinkReturnTarget.shouldPaste(
                        returnTargetPID: isBackInFront ? returnTarget?.processIdentifier : nil,
                        frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                        ownPID: ProcessInfo.processInfo.processIdentifier
                    ) {
                        appState.showDeepLinkError(
                            "Couldn't return to the app you came from, so nothing was pasted. Use the Paste Last Dictation shortcut there instead."
                        )
                        return
                    }
                    await appState.handleDeepLink(link)
                    switch link {
                    case .history, .settings:
                        settingsManager.open(appState: appState)
                    case .transcribeFile:
                        fileTranscriptionManager.open(appState: appState)
                    case .scratchpad:
                        scratchpadManager.open(appState: appState)
                    case .startDictation, .stopDictation, .toggleDictation, .pasteLast:
                        break
                    }
                }
            }
        }

        // Show onboarding on first launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
            if !self.appState.hasCompletedOnboarding {
                OnboardingWindowManager.shared.open(appState: self.appState)
            }
        }
    }

    /// The app a confirmed deep link should act on (#337). macOS brings
    /// VocaMac forward to deliver the URL, so the frontmost app is usually
    /// VocaMac by now; fall back to the last other app the user was in.
    /// The exact instance is kept, not looked up by bundle ID: with two
    /// copies of an app running, the first match may not be the user's.
    private static func deepLinkReturnTarget(lastActive: NSRunningApplication?) -> NSRunningApplication? {
        let frontmost = NSWorkspace.shared.frontmostApplication
        guard let bundleID = DeepLinkReturnTarget.bundleIdentifier(
            frontmost: frontmost?.bundleIdentifier,
            lastActive: lastActive?.bundleIdentifier,
            ownBundleIdentifier: Bundle.main.bundleIdentifier
        ) else { return nil }
        return frontmost?.bundleIdentifier == bundleID ? frontmost : lastActive
    }

    /// Put `app` back in front and wait (up to a second) until it is, so a
    /// paste or recording that follows targets it rather than VocaMac.
    /// False when it quit or didn't come forward, or lost focus again while
    /// it restored its window.
    @MainActor
    private static func reactivate(_ app: NSRunningApplication) async -> Bool {
        guard !app.isTerminated else { return false }
        NSApp.yieldActivation(to: app)
        app.activate()
        func isFront() -> Bool {
            NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        }
        for _ in 0..<20 {
            if isFront() {
                // Let the app restore its key window and focused field.
                try? await Task.sleep(for: .milliseconds(100))
                if isFront() { return true }
                break
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        VocaLogger.warning(.general, "Could not bring \(app.localizedName ?? "the previous app") back in front after a deep link")
        return false
    }

    /// Terminate any other running instances of VocaMac
    private static func ensureSingleInstance() {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.vocamac.app")

        for app in runningApps where app.processIdentifier != currentPID {
            VocaLogger.info(.general, "Terminating previous instance (PID \(app.processIdentifier))")
            app.terminate()
        }

        // Also kill by process name for direct binary execution (no bundle ID).
        // Match the executable's own name, never a substring of the command
        // line: `tail -f ~/Library/Logs/VocaMac/…`, an editor with
        // `Sources/VocaMac/…` open, or `xcodebuild -scheme VocaMac` must not
        // be terminated. A running headless CLI job (e.g.
        // `VocaMac --transcribe-file ... --json`) is left alone too.
        //
        // Off the main thread: spawning `ps` and reading every process's
        // command line held up launch, and the bundled app's instances are
        // already ended above.
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            task.arguments = ["-axo", "pid=,ucomm=,args="]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()
                if let output = String(data: data, encoding: .utf8) {
                    for pid in previousGUIInstancePIDs(psOutput: output, currentPID: currentPID) {
                        VocaLogger.info(.general, "Killing previous VocaMac process (PID \(pid))")
                        kill(pid, SIGTERM)
                    }
                }
            } catch {
                // ps not found or failed — not critical
            }
        }
    }

    /// PIDs of other GUI VocaMac processes in `ps -axo pid=,ucomm=,args=`
    /// output: the executable name must be exactly `VocaMac`, and headless CLI
    /// invocations (see `CLICommand.cliFlags`) are skipped.
    nonisolated static func previousGUIInstancePIDs(psOutput: String, currentPID: Int32) -> [Int32] {
        psOutput.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count >= 2, let pid = Int32(fields[0]), pid != currentPID,
                  fields[1] == "VocaMac" else { return nil }
            let arguments = fields.count > 2 ? fields[2].split(separator: " ").map(String.init) : []
            guard !arguments.contains(where: CLICommand.cliFlags.contains) else { return nil }
            return pid
        }
    }
}

// MARK: - Menu Bar Icon

/// The five-bar VocaMac mark in the menu bar, at 18 points, in the state
/// the Overlay board draws:
///
///   • Ready            → template (follows the menu bar)
///   • Listening        → accent (#0F6B57 on a light bar, #55C2A0 on a dark one)
///   • Working          → template at 55% with a dot
///   • Command Mode     → violet (#5E3BC4 / #BBA4FF)
///   • Needs attention  → the mark with an orange badge (a permission or an error)
///   • Off              → template at 35% (a model is still on its way)
///
/// Colours only appear while something is happening. MenuBarExtra strips
/// SwiftUI colours, so coloured states are drawn into a non-template
/// `NSImage`; their colours resolve against the menu bar's appearance when
/// the image draws.
struct MenuBarIcon: View {
    let appStatus: AppStatus
    var isCommandMode = false
    var readiness: MenuBarReadiness = .ready
    /// Says what the app is doing or needs ("VocaMac, recording").
    var accessibilityLabel = "VocaMac"

    var body: some View {
        Image(nsImage: makeMenuBarIcon())
            .accessibilityLabel(accessibilityLabel)
    }

    private func makeMenuBarIcon() -> NSImage {
        let style = MenuBarIconStyle.style(for: appStatus, isCommandMode: isCommandMode, readiness: readiness)
        let image = Self.image(for: MenuBarGlyphState(style: style))
        // The status item reads the image's description too.
        image.accessibilityDescription = accessibilityLabel
        return image
    }

    /// Canvas: the 18-point mark plus room for its badge to the upper right
    /// and its dot to the lower right.
    static let canvasSize = NSSize(width: 22, height: 22)
    /// Where the 18-point mark sits in the canvas (AppKit coordinates).
    static let glyphRect = NSRect(x: 1, y: 2, width: 18, height: 18)

    /// Draws one state of the mark.
    static func image(for state: MenuBarGlyphState) -> NSImage {
        let glyphRect = Self.glyphRect
        let glyph = CGPath.calmBrandMark(in: glyphRect)
        let image = NSImage(size: canvasSize, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            func strokeMark(_ color: NSColor) {
                context.saveGState()
                context.addPath(glyph)
                context.setLineWidth(2.2 * glyphRect.width / 22)
                context.setLineCap(.round)
                context.setStrokeColor(color.cgColor)
                context.strokePath()
                context.restoreGState()
            }
            func fillDot(_ rect: NSRect, _ color: NSColor) {
                context.setFillColor(color.cgColor)
                context.fillEllipse(in: rect)
            }
            switch state {
            case .ready:
                strokeMark(.black)
            case .listening:
                strokeMark(CalmNSColor.accent)
            case .working:
                strokeMark(NSColor.black.withAlphaComponent(0.55))
                // 6 points, 2 past the mark's right edge and 1 below it.
                fillDot(NSRect(x: glyphRect.maxX - 4, y: glyphRect.minY - 1, width: 6, height: 6), .black)
            case .commandMode:
                strokeMark(CalmNSColor.violet)
            case .needsAttention:
                strokeMark(.labelColor)
                // 7 points, 3 past the right edge and 2 above the top.
                fillDot(
                    NSRect(x: glyphRect.maxX - 4, y: glyphRect.maxY - 5, width: 7, height: 7),
                    CalmNSColor.rgb(0xE08A00)
                )
            case .off:
                strokeMark(NSColor.black.withAlphaComponent(0.35))
            }
            return true
        }
        image.isTemplate = state.isTemplate
        return image
    }
}

/// The six menu bar states on the Overlay board, from the icon style.
enum MenuBarGlyphState: Equatable {
    case ready, listening, working, commandMode, needsAttention, off

    init(style: MenuBarIconStyle) {
        switch style {
        case .systemSymbolTemplate: self = .ready
        case .brandMarkTinted: self = .listening
        case .notReadyTemplate(let badged): self = badged ? .needsAttention : .off
        case .systemSymbol(let name):
            switch name {
            case "wand.and.stars": self = .commandMode
            case "ellipsis.circle": self = .working
            default: self = .needsAttention
            }
        }
    }

    /// Template states follow the menu bar's own colour; coloured ones don't.
    var isTemplate: Bool {
        switch self {
        case .ready, .working, .off: return true
        case .listening, .commandMode, .needsAttention: return false
        }
    }
}

extension CGPath {
    /// The five-bar mark (22-point grid) scaled into `rect`. The bars are
    /// symmetric top to bottom, so AppKit's flipped y needs no correction.
    static func calmBrandMark(in rect: NSRect) -> CGPath {
        let scale = rect.width / 22
        let path = CGMutablePath()
        let bars: [(x: CGFloat, top: CGFloat, bottom: CGFloat)] = [
            (5, 9.5, 12.5), (8.3, 7, 15), (11.6, 4.5, 17.5), (14.9, 7.5, 14.5), (18, 9.5, 12.5),
        ]
        for bar in bars {
            path.move(to: CGPoint(x: rect.minX + bar.x * scale, y: rect.minY + bar.top * scale))
            path.addLine(to: CGPoint(x: rect.minX + bar.x * scale, y: rect.minY + bar.bottom * scale))
        }
        return path
    }
}
