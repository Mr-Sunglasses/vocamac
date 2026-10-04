// VocaPaper.swift
// VocaMac
//
// The paper itself: a fine grain over the canvas and the scenery, and the
// paper-waveform mark that stands for VocaMac in the menu bar and headers.

import AppKit
import SwiftUI

// MARK: - Grain

/// A tile of fine, fixed noise. Laid over a surface at low opacity it reads as
/// the tooth of paper rather than a flat fill. Built once; tiling it costs no
/// more than an image fill.
enum PaperGrain {
    static let tile: NSImage = {
        let side = 128
        var generator = SplitMix64(seed: 0x5EED_CAFE)
        var pixels = [UInt8](repeating: 0, count: side * side)
        for index in pixels.indices {
            pixels[index] = UInt8(truncatingIfNeeded: generator.next() >> 56)
        }
        let image = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let base = buffer.baseAddress,
                  let context = CGContext(
                    data: base, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return nil }
            return context.makeImage()
        }
        guard let image else { return NSImage(size: NSSize(width: side, height: side)) }
        // Half-size points: two pixels of noise per point on Retina reads as
        // grain, one point per pixel reads as static.
        return NSImage(cgImage: image, size: NSSize(width: side / 2, height: side / 2))
    }()

    /// A deterministic generator, so the grain is identical on every launch.
    private struct SplitMix64 {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

/// The grain as a view: tiled noise blended softly over what is beneath.
struct PaperGrainOverlay: View {
    var intensity: Double = 1

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: PaperGrain.tile)
            .resizable(resizingMode: .tile)
            .blendMode(colorScheme == .dark ? .softLight : .multiply)
            .opacity((colorScheme == .dark ? 0.05 : 0.035) * intensity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// The paper canvas: the warm ground with its grain.
    func vocaPaperBackground() -> some View {
        background {
            ZStack {
                VocaDesign.canvas
                PaperGrainOverlay()
            }
            .ignoresSafeArea()
        }
    }
}
