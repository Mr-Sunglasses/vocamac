// CalmModelsSettings.swift
// VocaMac
//
// Settings › Models (Speech to text and Writing AI tabs) and its All models
// sub-page. Placeholders from the v3 shell; the pages replace these bodies.

import SwiftUI

/// Settings › Models: the model picker. Its tab lives on the navigator
/// (`CalmNavigator.modelsTab`) so other pages can open Writing AI.
struct CalmModelsSettings: View {
    var body: some View {
        CalmPage(.sheet) {
            CalmPageHeader("Models")
        }
    }
}

/// Settings › Models › All models (sub-page).
struct CalmAllModelsSettings: View {
    var body: some View {
        CalmPage(.sheet) {
            CalmSubPageHeader("All models")
        }
    }
}
