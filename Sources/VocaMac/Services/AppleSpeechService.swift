// AppleSpeechService.swift
// VocaMac
//
// Transcription via Apple's SpeechAnalyzer/SpeechTranscriber (macOS 26+).
// Model assets are downloaded and managed by the system, so this engine
// needs no download UI and adds nothing to VocaMac's model storage.
//
// The implementation is compiled only with an SDK that ships the
// SpeechAnalyzer API (Xcode 26+); older toolchains build a stub that reports
// the engine as unavailable so CI on earlier macOS keeps working.

import Foundation
import AVFoundation
#if canImport(Speech)
import Speech
#endif

// MARK: - AppleSpeechError

enum AppleSpeechError: LocalizedError {
    case unsupportedSystem
    case modelNotLoaded
    case localeNotSupported(String)
    case audioFormatUnavailable
    case transcriptionFailed(reason: String)
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .unsupportedSystem:
            return "Apple Speech requires macOS 26 or later."
        case .modelNotLoaded:
            return "Apple Speech is not prepared. Please load the model first."
        case .localeNotSupported(let locale):
            return "Apple Speech does not support the language '\(locale)' on this Mac."
        case .audioFormatUnavailable:
            return "Apple Speech could not negotiate an audio format."
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .emptyAudio:
            return "No audio data to transcribe."
        }
    }
}

// MARK: - AppleSpeechService

final class AppleSpeechService: @unchecked Sendable {

    // MARK: - Properties

    /// Whether the running system and the SDK this binary was built with
    /// both support SpeechAnalyzer.
    static var isRuntimeSupported: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }

    /// Whether the engine has been prepared (assets checked/installed)
    private var isPrepared = false

    var isModelLoaded: Bool { isPrepared }

    var loadedModelName: String? { isPrepared ? ModelSize.appleSpeech.rawValue : nil }

    // MARK: - Model Management

    /// Prepare the system speech engine: resolves the user's locale and asks
    /// the OS to install transcription assets if they are missing.
    func loadModel(
        onPhaseChange: ((String) -> Void)? = nil
    ) async throws {
        #if compiler(>=6.2)
        guard #available(macOS 26.0, *) else { throw AppleSpeechError.unsupportedSystem }

        VocaLogger.info(.appleSpeechService, "Preparing Apple Speech (system engine)...")
        let startTime = CFAbsoluteTimeGetCurrent()

        onPhaseChange?("Checking speech assets…")
        try await AppleSpeechEngine.prepareAssets(for: Locale.current, onPhaseChange: onPhaseChange)
        isPrepared = true

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        VocaLogger.info(.appleSpeechService, "Apple Speech ready in \(String(format: "%.2f", elapsed))s")
        #else
        throw AppleSpeechError.unsupportedSystem
        #endif
    }

    func unloadModel() {
        isPrepared = false
    }

    // MARK: - Transcription

    /// Transcribe audio data to text using the system speech engine.
    /// - Parameters:
    ///   - audioData: Array of Float32 PCM samples at 16kHz mono
    ///   - language: ISO 639-1 language code, or nil to use the system locale.
    ///     Translation and custom vocabulary are not supported by this engine.
    func transcribe(
        audioData: [Float],
        language: String? = nil
    ) async throws -> VocaTranscription {
        #if compiler(>=6.2)
        guard #available(macOS 26.0, *) else { throw AppleSpeechError.unsupportedSystem }
        guard isPrepared else { throw AppleSpeechError.modelNotLoaded }
        guard !audioData.isEmpty else { throw AppleSpeechError.emptyAudio }

        let audioLengthSeconds = Double(audioData.count) / 16000.0
        VocaLogger.info(.appleSpeechService, "Apple Speech transcribing \(String(format: "%.1f", audioLengthSeconds))s of audio...")

        let startTime = CFAbsoluteTimeGetCurrent()
        let requestedLocale = language.map { Locale(identifier: $0) } ?? Locale.current

        do {
            let text = try await AppleSpeechEngine.transcribe(
                samples: audioData,
                locale: requestedLocale
            )

            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            VocaLogger.info(.appleSpeechService, "Apple Speech transcription completed in \(String(format: "%.2f", elapsed))s")
            VocaLogger.info(.appleSpeechService, "Result: \(text.prefix(100))...")

            return VocaTranscription(
                text: text,
                duration: elapsed,
                detectedLanguage: language ?? requestedLocale.language.languageCode?.identifier ?? "auto",
                audioLengthSeconds: audioLengthSeconds,
                modelUsed: .appleSpeech
            )
        } catch let error as AppleSpeechError {
            throw error
        } catch {
            throw AppleSpeechError.transcriptionFailed(reason: error.localizedDescription)
        }
        #else
        throw AppleSpeechError.unsupportedSystem
        #endif
    }
}

// MARK: - AppleSpeechEngine (SpeechAnalyzer wrapper)

#if compiler(>=6.2)
@available(macOS 26.0, *)
enum AppleSpeechEngine {

    /// Sample rate of the audio VocaMac's AudioEngine produces.
    private static let inputSampleRate: Double = 16_000

    /// Resolve a requested locale to one SpeechTranscriber supports.
    /// Falls back from an exact BCP-47 match to a same-language match.
    static func resolveSupportedLocale(matching locale: Locale) async -> Locale? {
        let supported = await SpeechTranscriber.supportedLocales
        if let exact = supported.first(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) {
            return exact
        }
        return supported.first {
            $0.language.languageCode == locale.language.languageCode
        }
    }

    /// Ensure the system has transcription assets installed for the locale.
    static func prepareAssets(
        for locale: Locale,
        onPhaseChange: ((String) -> Void)? = nil
    ) async throws {
        guard let resolved = await resolveSupportedLocale(matching: locale) else {
            throw AppleSpeechError.localeNotSupported(locale.identifier)
        }

        let transcriber = SpeechTranscriber(
            locale: resolved,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            onPhaseChange?("Downloading speech assets…")
            VocaLogger.info(.appleSpeechService, "Downloading system speech assets for \(resolved.identifier)...")
            try await request.downloadAndInstall()
        }
    }

    /// Transcribe a full clip of 16kHz mono Float32 samples.
    static func transcribe(samples: [Float], locale: Locale) async throws -> String {
        guard let resolved = await resolveSupportedLocale(matching: locale) else {
            throw AppleSpeechError.localeNotSupported(locale.identifier)
        }

        let transcriber = SpeechTranscriber(
            locale: resolved,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        // Assets for the app's warm-up locale are installed at load time, but
        // the user may dictate in a different language — install on demand.
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])

        guard let analysisFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            throw AppleSpeechError.audioFormatUnavailable
        }

        // Collect final results concurrently while audio is analyzed.
        let collector = Task { () -> String in
            var pieces: [String] = []
            for try await result in transcriber.results where result.isFinal {
                pieces.append(String(result.text.characters))
            }
            return pieces.joined()
        }

        let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        try await analyzer.start(inputSequence: inputSequence)

        let inputBuffer = try pcmBuffer(from: samples)
        let analysisBuffer = try convert(inputBuffer, to: analysisFormat)
        inputBuilder.yield(AnalyzerInput(buffer: analysisBuffer))
        inputBuilder.finish()

        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let text = try await collector.value
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Audio plumbing

    /// Wrap raw samples in an AVAudioPCMBuffer (16kHz mono Float32).
    private static func pcmBuffer(from samples: [Float]) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputSampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else {
            throw AppleSpeechError.audioFormatUnavailable
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channelData = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { source in
                channelData[0].update(from: source.baseAddress!, count: samples.count)
            }
        }
        return buffer
    }

    /// Convert a buffer to the analyzer's preferred format if they differ.
    private static func convert(
        _ buffer: AVAudioPCMBuffer,
        to format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        if buffer.format == format {
            return buffer
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            throw AppleSpeechError.audioFormatUnavailable
        }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 1024)
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw AppleSpeechError.audioFormatUnavailable
        }

        var fed = false
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, outStatus in
            if fed {
                outStatus.pointee = .endOfStream
                return nil
            }
            fed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let conversionError {
            throw AppleSpeechError.transcriptionFailed(reason: conversionError.localizedDescription)
        }
        return converted
    }
}
#endif
