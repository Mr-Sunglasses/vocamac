// CalmAboutSettings.swift
// VocaMac
//
// Settings › About, opened from the version in the sheet menu's footer.
// Placeholder from the v3 shell; the page replaces this body.

import SwiftUI

/// Settings › About: identity, updates, this Mac, credits, links.
struct CalmAboutSettings: View {
    var body: some View {
        CalmPage(.sheet) {
            HStack(spacing: 20) {
                CalmBrandMark(size: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("VocaMac").calmType(.title).accessibilityAddTraits(.isHeader)
                    Text("Version \(CalmSettingsMenu.appVersion)").calmType(.description)
                }
            }
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }
}
