// CalmHomePage.swift
// VocaMac
//
// Home: the dictation feed (old History page) and the side card.
// Placeholder from the v3 shell; the page itself replaces this body.

import SwiftUI

/// Home: the dictation feed (old History page) and the side card.
struct CalmHomePage: View {
    var body: some View {
        CalmPage(.list) {
            CalmPageHeader("Welcome back")
        }
    }
}
