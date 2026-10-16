// CalmGeneralSettings.swift
// VocaMac
//
// Settings › General: dictation key, hands-free, microphone, languages, overlay.
// Placeholder from the v3 shell; the page itself replaces this body.

import SwiftUI

/// Settings › General: dictation key, hands-free, microphone, languages, overlay.
struct CalmGeneralSettings: View {
    var body: some View {
        CalmPage(.sheet) {
            CalmPageHeader("General")
        }
    }
}
