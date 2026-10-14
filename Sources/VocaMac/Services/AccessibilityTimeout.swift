// AccessibilityTimeout.swift
// VocaMac
//
// One fixed messaging timeout for the system-wide Accessibility element.

import ApplicationServices

enum AccessibilityTimeout {

    /// Timeout for questions put to the system-wide element (which element
    /// has focus), and the default for any element without its own.
    ///
    /// Setting a timeout on the system-wide element sets it for the whole
    /// process. The paste path asked for 0.1 s and the selection reader for
    /// 0.5 s, each just before its own query, so either could run with the
    /// other's while both were in flight. It is now set once; elements that
    /// need another value set it on themselves, which applies to that
    /// element alone. Selection reads keep 0.5 s on the frontmost app's own
    /// element, which they ask as well.
    static let systemWideSeconds: Float = 0.25

    private static let isConfigured: Bool = {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), systemWideSeconds)
        return true
    }()

    /// The system-wide element, with the process-wide timeout applied once.
    static func systemWideElement() -> AXUIElement {
        _ = isConfigured
        return AXUIElementCreateSystemWide()
    }
}
