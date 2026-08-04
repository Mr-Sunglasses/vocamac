// SherpaService.swift
// VocaMac
//
// Transcription via sherpa-onnx (ONNX Runtime, CPU-only). Serves the
// specialized community models: Moonshine v2 (English), SenseVoice
// (Chinese/Asian), GigaAM (Russian), and Canary (European languages).
//
// Uses the sherpa-onnx C API directly for recognizer lifecycle and decoding
// so failures surface as thrown errors; the vendored config builders in
// Vendor/SherpaOnnxConfigBuilders.swift construct the C config structs.

import Foundation
import SherpaOnnxC

// MARK: - SherpaError

enum SherpaError: LocalizedError {
    case modelNotLoaded
    case unknownModel(String)
    case modelFilesMissing(String)
    case initializationFailed(reason: String)
    case transcriptionFailed(reason: String)
    case emptyAudio

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No ONNX model is loaded. Please load a model first."
        case .unknownModel(let name):
            return "Unknown ONNX model: \(name)"
        case .modelFilesMissing(let path):
            return "Model files are missing at: \(path)"
        case .initializationFailed(let reason):
            return "Failed to initialize the ONNX model: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .emptyAudio:
            return "No audio data to transcribe."
        }
    }
}

// MARK: - SherpaService

final class SherpaService: @unchecked Sendable {

    // MARK: - Storage

    /// Root directory where sherpa-onnx model directories are extracted.
    /// Lives next to the WhisperKit model storage under Application Support.
    static var storageRoot: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("VocaMac")
            .appendingPathComponent("models")
            .appendingPathComponent("sherpa-onnx")
    }

    /// Directory a spec's files live in once extracted.
    static func modelDirectory(for spec: SherpaModelSpec) -> URL {
        storageRoot.appendingPathComponent(spec.directoryName, isDirectory: true)
    }

    /// Whether every file the model needs exists on disk.
    static func modelFilesExist(for spec: SherpaModelSpec) -> Bool {
        let directory = modelDirectory(for: spec)
        return spec.requiredFiles.allSatisfy {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path)
        }
    }

    // MARK: - Properties

    /// The active C recognizer (created when a model is loaded)
    private var recognizer: OpaquePointer?

    /// Which model is currently loaded
    private var loadedSize: ModelSize?

    /// Serializes recognizer lifecycle against decoding
    private let recognizerLock = NSLock()

    var isModelLoaded: Bool { recognizer != nil }

    var loadedModelName: String? { loadedSize?.rawValue }

    deinit {
        unloadModel()
    }

    // MARK: - Model Management

    /// Load a sherpa-onnx model from its extracted directory.
    func loadModel(
        name modelName: String? = nil,
        onPhaseChange: ((String) -> Void)? = nil
    ) async throws {
        unloadModel()

        guard let size = modelName.flatMap(ModelSize.init(rawValue:)),
              let spec = SherpaModelCatalog.spec(for: size) else {
            throw SherpaError.unknownModel(modelName ?? "nil")
        }

        let directory = Self.modelDirectory(for: spec)
        guard Self.modelFilesExist(for: spec) else {
            throw SherpaError.modelFilesMissing(directory.path)
        }

        VocaLogger.info(.sherpaService, "Loading ONNX model: \(size.rawValue)...")
        let startTime = CFAbsoluteTimeGetCurrent()
        onPhaseChange?("Loading ONNX model…")

        // The user's language preference influences config for SenseVoice
        // (recognition language) and Canary (source language). Both are fixed
        // at load time by the C API, so AppState reloads the active model when
        // the preference changes (see reloadModelForLanguageChangeIfNeeded).
        let preferredLanguage = UserDefaults.standard.string(forKey: PreferenceKey.selectedLanguage) ?? "auto"

        var config = Self.recognizerConfig(for: spec, in: directory, language: preferredLanguage)

        let created: OpaquePointer? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: SherpaOnnxCreateOfflineRecognizer(&config))
            }
        }

        guard let created else {
            throw SherpaError.initializationFailed(reason: "sherpa-onnx rejected the model files at \(directory.path)")
        }

        adopt(recognizer: created, size: size)

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        VocaLogger.info(.sherpaService, "ONNX model loaded in \(String(format: "%.2f", elapsed))s")
    }

    /// Take ownership of a freshly created recognizer.
    private func adopt(recognizer created: OpaquePointer, size: ModelSize) {
        recognizerLock.lock()
        defer { recognizerLock.unlock() }
        recognizer = created
        loadedSize = size
    }

    /// Unload the current model and free memory
    func unloadModel() {
        recognizerLock.lock()
        if let recognizer {
            SherpaOnnxDestroyOfflineRecognizer(recognizer)
            VocaLogger.info(.sherpaService, "ONNX model unloaded")
        }
        recognizer = nil
        loadedSize = nil
        recognizerLock.unlock()
    }

    // MARK: - Transcription

    /// Transcribe audio data to text.
    /// - Parameters:
    ///   - audioData: Array of Float32 PCM samples at 16kHz mono
    ///   - language: ISO 639-1 language code; only used to label the result.
    ///     Model language behavior is fixed at load time (see loadModel).
    func transcribe(
        audioData: [Float],
        language: String? = nil
    ) async throws -> VocaTranscription {
        guard isModelLoaded, let size = loadedSize else {
            throw SherpaError.modelNotLoaded
        }

        guard !audioData.isEmpty else {
            throw SherpaError.emptyAudio
        }

        let audioLengthSeconds = Double(audioData.count) / 16000.0
        VocaLogger.info(.sherpaService, "ONNX transcribing \(String(format: "%.1f", audioLengthSeconds))s of audio...")

        let startTime = CFAbsoluteTimeGetCurrent()

        let decoded: (text: String, lang: String)? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                continuation.resume(returning: self?.decodeLocked(samples: audioData))
            }
        }

        guard let decoded else {
            throw SherpaError.transcriptionFailed(reason: "The model was unloaded during transcription.")
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)

        VocaLogger.info(.sherpaService, "ONNX transcription completed in \(String(format: "%.2f", elapsed))s")
        VocaLogger.info(.sherpaService, "Result: \(text.prefix(100))...")

        // SenseVoice reports the detected language; other models are
        // monolingual or fixed at load time.
        let detectedLanguage = decoded.lang.isEmpty ? (language ?? "auto") : decoded.lang

        return VocaTranscription(
            text: text,
            duration: elapsed,
            detectedLanguage: detectedLanguage,
            audioLengthSeconds: audioLengthSeconds,
            modelUsed: size
        )
    }

    /// Run one decode against the active recognizer. Returns nil if no model
    /// is loaded. Called off the main thread; holds the lock so the
    /// recognizer cannot be destroyed mid-decode.
    private func decodeLocked(samples: [Float]) -> (text: String, lang: String)? {
        recognizerLock.lock()
        defer { recognizerLock.unlock() }

        guard let recognizer,
              let stream = SherpaOnnxCreateOfflineStream(recognizer) else {
            return nil
        }
        defer { SherpaOnnxDestroyOfflineStream(stream) }

        samples.withUnsafeBufferPointer { buffer in
            SherpaOnnxAcceptWaveformOffline(stream, 16000, buffer.baseAddress, Int32(buffer.count))
        }
        SherpaOnnxDecodeOfflineStream(recognizer, stream)

        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else {
            return ("", "")
        }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }

        let text = result.pointee.text.map { String(cString: $0) } ?? ""
        let lang = result.pointee.lang.map { String(cString: $0) } ?? ""
        // SenseVoice language tags look like "<|zh|>" — strip the markers.
        let cleanLang = lang.replacingOccurrences(of: "<|", with: "").replacingOccurrences(of: "|>", with: "")
        return (text, cleanLang)
    }

    // MARK: - Configuration

    /// Build the C recognizer config for a model spec.
    private static func recognizerConfig(
        for spec: SherpaModelSpec,
        in directory: URL,
        language: String
    ) -> SherpaOnnxOfflineRecognizerConfig {
        let path = { (file: String) in directory.appendingPathComponent(file).path }
        let numThreads = min(4, max(2, SystemInfo.recommendedThreadCount))

        let modelConfig: SherpaOnnxOfflineModelConfig
        switch spec.kind {
        case .moonshine(let encoder, let mergedDecoder):
            modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: path(spec.tokensFile),
                numThreads: numThreads,
                moonshine: sherpaOnnxOfflineMoonshineModelConfig(
                    encoder: path(encoder),
                    mergedDecoder: path(mergedDecoder)
                )
            )
        case .senseVoice(let model):
            let supported: Set<String> = ["zh", "en", "ja", "ko", "yue"]
            let senseVoiceLanguage = supported.contains(language) ? language : "auto"
            modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: path(spec.tokensFile),
                numThreads: numThreads,
                senseVoice: sherpaOnnxOfflineSenseVoiceModelConfig(
                    model: path(model),
                    language: senseVoiceLanguage,
                    useInverseTextNormalization: true
                )
            )
        case .nemoCtc(let model):
            modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: path(spec.tokensFile),
                nemoCtc: sherpaOnnxOfflineNemoEncDecCtcModelConfig(model: path(model)),
                numThreads: numThreads
            )
        case .canary(let encoder, let decoder, let supportedLanguages):
            let canaryLanguage = supportedLanguages.contains(language) ? language : "en"
            modelConfig = sherpaOnnxOfflineModelConfig(
                tokens: path(spec.tokensFile),
                numThreads: numThreads,
                canary: sherpaOnnxOfflineCanaryModelConfig(
                    encoder: path(encoder),
                    decoder: path(decoder),
                    srcLang: canaryLanguage,
                    tgtLang: canaryLanguage
                )
            )
        }

        return sherpaOnnxOfflineRecognizerConfig(
            featConfig: sherpaOnnxFeatureConfig(),
            modelConfig: modelConfig
        )
    }
}
