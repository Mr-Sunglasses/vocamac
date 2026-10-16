// CalmStylesPage.swift
// VocaMac
//
// Styles: writing styles per kind of app, and typed-text formatting.
// Placeholder from the v3 shell; the page itself replaces this body.

import SwiftUI

/// Styles: writing styles per kind of app, and typed-text formatting.
struct CalmStylesPage: View {
    var body: some View {
        CalmPage(.list, spacing: 24) {
            CalmPageHeader("Styles", description: "How your words look in each kind of app. Pick one per group.")
        }
    }
}
