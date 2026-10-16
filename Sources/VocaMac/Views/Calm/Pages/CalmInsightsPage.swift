// CalmInsightsPage.swift
// VocaMac
//
// Insights: totals, streak, heatmap and personal bests (old Stats page).
// Placeholder from the v3 shell; the page itself replaces this body.

import SwiftUI

/// Insights: totals, streak, heatmap and personal bests (old Stats page).
struct CalmInsightsPage: View {
    var body: some View {
        CalmPage(.list, spacing: 20) {
            CalmPageHeader("Insights")
        }
    }
}
