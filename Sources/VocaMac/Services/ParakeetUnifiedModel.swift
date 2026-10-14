// ParakeetUnifiedModel.swift
// VocaMac
//
// Files for NVIDIA Parakeet Unified 0.6B (English), which FluidAudio runs
// through `UnifiedAsrManager` rather than the TDT `AsrManager` the other
// Parakeet models use. VocaMac uses its batch export: a full-attention 15 s
// encoder, with longer audio decoded in overlapping windows. It writes
// punctuation, capitals, and numbers as digits ("35.3%").

import Foundation
import FluidAudio

enum ParakeetUnifiedModel {

    /// int8 is FluidAudio's default: the same LibriSpeech WER as fp16 and the
    /// same Neural Engine speed on M-series Macs, at half the download.
    static let encoderPrecision: UnifiedEncoderPrecision = .int8

    /// The FluidAudio download variant with the batch (offline) encoder.
    static let downloadVariant = "offline"

    /// FluidAudio's model cache; the repository folder sits inside it.
    static var modelsRoot: URL { MLModelConfigurationUtils.defaultModelsDirectory() }

    /// Where the model's files are, the same place `UnifiedAsrManager`
    /// loads from and downloads to.
    static var directory: URL { MLModelConfigurationUtils.defaultModelsDirectory(for: .parakeetUnified) }

    /// The files a batch load reads.
    static var requiredFiles: [String] {
        [
            ModelNames.ParakeetUnified.offlineEncoderFile(precision: encoderPrecision),
            ModelNames.ParakeetUnified.decoderFile,
            ModelNames.ParakeetUnified.jointDecisionFile,
            ModelNames.ParakeetUnified.vocab,
        ]
    }

    /// Whether every file a batch load reads is on disk, and no compiled
    /// model is missing its program (an interrupted download).
    static func modelsExist(at directory: URL = directory) -> Bool {
        let manager = FileManager.default
        return requiredFiles.allSatisfy { manager.fileExists(atPath: directory.appendingPathComponent($0).path) }
            && CoreMLModelCache.isComplete(directory)
    }

    /// Download the batch model into FluidAudio's cache without loading it.
    static func download(onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try await ModelHub.download(.parakeetUnified, to: modelsRoot, variant: downloadVariant) { progress in
            onProgress(progress.fractionCompleted)
        }
    }

    /// A manager for the batch model, not yet loaded.
    static func makeManager() -> UnifiedAsrManager {
        UnifiedAsrManager(encoderPrecision: encoderPrecision)
    }
}
