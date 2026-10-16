// CalmCleanupSettings.swift
// VocaMac
//
// Settings › Smart Cleanup.
// Placeholder from the v3 shell; the page itself replaces this body.

import SwiftUI

/// Settings › Smart Cleanup.
struct CalmCleanupSettings: View {
    var body: some View {
        CalmPage(.sheet) {
            CalmPageHeader("Smart Cleanup", description: "Tidies what you said before it’s typed. Runs on this Mac.")
        }
    }
}
