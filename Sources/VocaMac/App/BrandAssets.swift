// BrandAssets.swift
// VocaMac

import AppKit
import SwiftUI

/// Provides the Voca brand artwork bundled with the app.
enum BrandAssets {
    /// Loads a bundled image from the Swift package resource bundle.
    static func image(named name: String, fileExtension: String = "png") -> NSImage? {
        let bundle = Bundle.module
        let url = bundle.url(forResource: name, withExtension: fileExtension, subdirectory: "Resources")
            ?? bundle.url(forResource: name, withExtension: fileExtension)
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }

    /// The circular Voca logo used in app-facing surfaces.
    static var logo: NSImage? {
        image(named: "voca-logo-512")
    }
}

/// Renders the canonical Voca logo with a safe fallback for development builds.
struct BrandLogoView: View {
    let size: CGFloat

    var body: some View {
        if let logo = BrandAssets.logo {
            Image(nsImage: logo)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(.blue)
                .frame(width: size, height: size)
        }
    }
}
