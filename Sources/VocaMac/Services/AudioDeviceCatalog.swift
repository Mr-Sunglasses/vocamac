import Foundation
import Observation

/// Shared picker data. Core Audio property reads can wait on device drivers;
/// never perform them while SwiftUI is constructing a page or opening a menu.
@MainActor
@Observable
final class AudioDeviceCatalog {
    static let shared = AudioDeviceCatalog()

    private(set) var devices: [AudioDevice] = []
    private(set) var hasLoaded = false
    private(set) var isRefreshing = false
    @ObservationIgnored private var needsRefresh = false
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private let enumerate: @Sendable () -> [AudioDevice]

    init(observeChanges: Bool = true,
         enumerate: @escaping @Sendable () -> [AudioDevice] = { AudioEngine.availableInputDevices() }) {
        self.enumerate = enumerate
        if observeChanges {
            observer = NotificationCenter.default.addObserver(
                forName: .vocaAudioDevicesChanged, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refresh(force: true)
                }
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Coalesces overlapping requests, retaining one follow-up scan if hardware
    /// changes during a scan. Cached visits require no driver calls.
    func refresh(force: Bool = false) async {
        if isRefreshing {
            needsRefresh = needsRefresh || force
            return
        }
        guard force || !hasLoaded else { return }
        isRefreshing = true
        repeat {
            needsRefresh = false
            let enumerate = enumerate
            let result = await Task.detached(priority: .userInitiated) {
                enumerate()
            }.value
            if devices != result { devices = result }
            hasLoaded = true
        } while needsRefresh
        isRefreshing = false
    }
}
