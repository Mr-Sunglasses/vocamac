// CalmAdvancedSettings.swift
// VocaMac
//
// Settings › Advanced and its Phone gateway sub-page. Placeholders from
// the v3 shell; the pages replace these bodies.

import SwiftUI

/// Settings › Advanced: permissions, phone gateway, logs, resource usage.
struct CalmAdvancedSettings: View {
    var body: some View {
        CalmPage(.sheet) {
            CalmPageHeader("Advanced")
        }
    }
}

/// Settings › Advanced › Phone gateway (sub-page).
struct CalmGatewaySettings: View {
    var body: some View {
        CalmPage(.sheet) {
            CalmSubPageHeader("Phone gateway")
        }
    }
}
