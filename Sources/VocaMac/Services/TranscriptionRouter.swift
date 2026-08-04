// TranscriptionRouter.swift
// VocaMac
//
// Routes model loading and transcription to the engine that owns the
// requested model. AppState talks to this single SpeechTranscribing facade
// and never needs to know which engine is active.

import Foundation

final class TranscriptionRouter: @unchecked Sendable {

    // MARK: - Engines

    private let whisper = WhisperService()
    private let parakeet = ParakeetService()
    private let appleSpeech = AppleSpeechService()
    private let sherpa = SherpaService()

    /// Engine that owns the currently loaded model.
    private(set) var activeEngine: TranscriptionEngine = .whisperKit

    // MARK: - Engine Resolution

    /// Resolve which engine owns a model identifier.
    ///
    /// Parakeet and Apple Speech models are identified by their ModelSize raw
    /// value; anything else (WhisperKit variant names like
    /// "openai_whisper-tiny", or nil for auto-select) belongs to WhisperKit.
    static func engine(forModelIdentifier identifier: String?) -> TranscriptionEngine {
        guard let identifier,
              let size = ModelSize(rawValue: identifier) else {
            return .whisperKit
        }
        return size.engine
    }

    // MARK: - SpeechTranscribing state

    var loadedModelName: String? {
        switch activeEngine {
        case .whisperKit:  return whisper.loadedModelName
        case .parakeet:    return parakeet.loadedModelName
        case .appleSpeech: return appleSpeech.loadedModelName
        case .sherpaOnnx:  return sherpa.loadedModelName
        }
    }

    var isModelLoaded: Bool {
        switch activeEngine {
        case .whisperKit:  return whisper.isModelLoaded
        case .parakeet:    return parakeet.isModelLoaded
        case .appleSpeech: return appleSpeech.isModelLoaded
        case .sherpaOnnx:  return sherpa.isModelLoaded
        }
    }
}

// MARK: - SpeechTranscribing Conformance

extension TranscriptionRouter: SpeechTranscribing {

    func _loadModel(name: String?, folder: URL?, onPhaseChange: ((String) -> Void)?) async throws {
        let engine = Self.engine(forModelIdentifier: name)

        // Free the previous engine's memory before loading the new model.
        // Each engine also unloads itself before loading, so only the
        // engines that are not the target need explicit unloading here.
        if engine != .whisperKit {
            whisper.unloadModel()
        }
        if engine != .parakeet {
            parakeet.unloadModel()
        }
        if engine != .appleSpeech {
            appleSpeech.unloadModel()
        }
        if engine != .sherpaOnnx {
            sherpa.unloadModel()
        }

        switch engine {
        case .whisperKit:
            try await whisper.loadModel(name: name, folder: folder, onPhaseChange: onPhaseChange)
        case .parakeet:
            try await parakeet.loadModel(name: name, onPhaseChange: onPhaseChange)
        case .appleSpeech:
            try await appleSpeech.loadModel(onPhaseChange: onPhaseChange)
        case .sherpaOnnx:
            try await sherpa.loadModel(name: name, onPhaseChange: onPhaseChange)
        }

        activeEngine = engine
    }

    func transcribe(
        audioData: [Float],
        language: String?,
        translate: Bool,
        vocabulary: String
    ) async throws -> VocaTranscription {
        switch activeEngine {
        case .whisperKit:
            return try await whisper.transcribe(
                audioData: audioData,
                language: language,
                translate: translate,
                vocabulary: vocabulary
            )
        case .parakeet:
            return try await parakeet.transcribe(audioData: audioData, language: language)
        case .appleSpeech:
            return try await appleSpeech.transcribe(audioData: audioData, language: language)
        case .sherpaOnnx:
            return try await sherpa.transcribe(audioData: audioData, language: language)
        }
    }
}
