// AudioSegmenter.swift
// VocaMac
//
// Splits a recording into segments short enough for engines that decode an
// utterance in a single pass. Cuts are placed at the quietest point near the
// target boundary so words are not sliced in half.

import Foundation

enum AudioSegmenter {

    /// Frame used when measuring loudness — 20ms at 16kHz.
    private static let frameLength = 320

    /// How far back from the target boundary to look for a quiet point.
    /// Long enough to reach the previous pause in normal speech.
    private static let searchWindowSeconds = 2.0

    /// Split `samples` into consecutive ranges no longer than `maxSeconds`.
    ///
    /// Audio already short enough is returned as a single range. Otherwise
    /// each cut is placed at the lowest-energy frame within the search window
    /// ending at the maximum length, which lands in a pause between words
    /// when there is one.
    static func segmentRanges(
        sampleCount: Int,
        maxSeconds: Double,
        sampleRate: Int = 16_000,
        energyAt: (Range<Int>) -> Float
    ) -> [Range<Int>] {
        let maxSamples = Int(maxSeconds * Double(sampleRate))
        guard maxSamples > 0, sampleCount > maxSamples else {
            return sampleCount > 0 ? [0..<sampleCount] : []
        }

        let searchSamples = min(Int(searchWindowSeconds * Double(sampleRate)), maxSamples / 2)
        var ranges: [Range<Int>] = []
        var start = 0

        while start < sampleCount {
            let remaining = sampleCount - start
            if remaining <= maxSamples {
                ranges.append(start..<sampleCount)
                break
            }

            let hardEnd = start + maxSamples
            let searchStart = max(start + frameLength, hardEnd - searchSamples)

            var quietestIndex = hardEnd
            var quietestEnergy = Float.greatestFiniteMagnitude
            var frameStart = searchStart
            while frameStart + frameLength <= hardEnd {
                let energy = energyAt(frameStart..<(frameStart + frameLength))
                if energy < quietestEnergy {
                    quietestEnergy = energy
                    quietestIndex = frameStart + frameLength / 2
                }
                frameStart += frameLength
            }

            // Never emit an empty or backwards range.
            let cut = max(start + frameLength, min(quietestIndex, hardEnd))
            ranges.append(start..<cut)
            start = cut
        }

        return ranges
    }

    /// Convenience wrapper that measures energy directly from the samples.
    static func segment(_ samples: [Float], maxSeconds: Double, sampleRate: Int = 16_000) -> [[Float]] {
        let ranges = segmentRanges(
            sampleCount: samples.count,
            maxSeconds: maxSeconds,
            sampleRate: sampleRate
        ) { range in
            var sum: Float = 0
            for i in range { sum += samples[i] * samples[i] }
            return sum / Float(range.count)
        }

        if ranges.count <= 1 {
            return samples.isEmpty ? [] : [samples]
        }
        return ranges.map { Array(samples[$0]) }
    }
}
