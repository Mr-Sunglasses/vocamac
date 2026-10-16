// CalmDictionaryPage.swift
// VocaMac
//
// Dictionary: vocabulary, replacements and suggestions.
// Placeholder from the v3 shell; the page itself replaces this body.

import SwiftUI

/// Dictionary: vocabulary, replacements and suggestions.
struct CalmDictionaryPage: View {
    var body: some View {
        CalmPage(.list, spacing: 22) {
            CalmPageHeader("Dictionary")
        }
    }
}
