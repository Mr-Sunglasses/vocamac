// CalmSnippetsPage.swift
// VocaMac
//
// Snippets: say a word, get the whole text.
// Placeholder from the v3 shell; the page itself replaces this body.

import SwiftUI

/// Snippets: say a word, get the whole text.
struct CalmSnippetsPage: View {
    var body: some View {
        CalmPage(.list, spacing: 22) {
            CalmPageHeader("Snippets")
        }
    }
}
