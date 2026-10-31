// LipReader.swift
// VocaMac
//
// Reads mouthed English from mouth crops: Auto-AVSR's visual speech
// recognition model (LRS3_V_WER19.1, encoder and CTC head) converted to
// Core ML, decoded greedily. English only: the model was trained on English
// TED talks and knows no other language.
//
// The model isn't bundled or downloaded: its weights carry the training
// data's research and non-commercial terms. It is built on this Mac with
// `scripts/convert-lip-reading-model.sh` (or imported) into
// ~/Library/Application Support/VocaMac/models/lip-reading/.
//
// The Core ML model accepts a fixed set of lengths (every 10 frames, 0.4 s,
// up to 30 s). `LipReadingWindow` widens each stretch of speech to one of
// them with real camera frames from around it, and splits longer speech.

import CoreML
import Foundation

// MARK: - Protocol

protocol LipReading: AnyObject, Sendable {
    /// The model is on this Mac.
    var isInstalled: Bool { get }
    /// Load the model ahead of the first read (it takes a few seconds).
    func prepare() async
    /// The words in `crops`: 25 frames a second, one of the model's lengths.
    func read(_ crops: [MouthCrop]) async throws -> String
    /// Free the loaded model.
    func unload()
}

enum LipReadingError: LocalizedError {
    case notInstalled
    case modelFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "The lip-reading model isn't installed. See Settings › Silent Mode."
        case .modelFailed(let detail): return "Lip reading failed: \(detail)"
        }
    }
}

// MARK: - Windows

enum LipReadingWindow {
    /// The model's frame rate.
    static let fps = 25.0
    /// The model's lengths are multiples of this many frames.
    static let step = 10
    static let minimumFrames = 10
    static let maximumFrames = 750

    /// The model length for `frames` frames: the next multiple of `step`.
    static func modelLength(for frames: Int) -> Int {
        min(maximumFrames, max(minimumFrames, Int((Double(frames) / Double(step)).rounded(.up)) * step))
    }

    /// Stretches of speech, joined while they fit in one read and split
    /// when one alone is too long. Seconds on the frames' clock.
    static func chunks(_ speaking: [ClosedRange<TimeInterval>]) -> [ClosedRange<TimeInterval>] {
        let longest = Double(maximumFrames) / fps - 0.4
        var result: [ClosedRange<TimeInterval>] = []
        for span in ArticulationDetector.merged(speaking) {
            var start = span.lowerBound
            while span.upperBound - start > longest {
                result.append(start...(start + longest))
                start += longest
            }
            let piece = start...span.upperBound
            if let last = result.last, piece.upperBound - last.lowerBound <= longest {
                result[result.count - 1] = last.lowerBound...piece.upperBound
            } else {
                result.append(piece)
            }
        }
        return result
    }

    /// The 25 fps frame times to read for `span`, widened to a model length
    /// evenly on both sides, and kept inside `available` where it allows.
    static func frameTimes(for span: ClosedRange<TimeInterval>, available: ClosedRange<TimeInterval>) -> [TimeInterval] {
        let frames = max(1, Int(((span.upperBound - span.lowerBound) * fps).rounded()))
        let length = modelLength(for: frames)
        let duration = Double(length - 1) / fps
        var start = (span.lowerBound + span.upperBound) / 2 - duration / 2
        // Slide into the recorded frames rather than repeat an edge frame.
        if start + duration > available.upperBound { start = available.upperBound - duration }
        if start < available.lowerBound { start = available.lowerBound }
        return (0..<length).map { start + Double($0) / fps }
    }

    /// The crop nearest each time. `crops` must be in time order.
    static func crops(at times: [TimeInterval], from crops: [MouthCrop]) -> [MouthCrop] {
        guard !crops.isEmpty else { return [] }
        var index = 0
        return times.map { time in
            while index + 1 < crops.count, abs(crops[index + 1].time - time) <= abs(crops[index].time - time) {
                index += 1
            }
            var crop = crops[index]
            crop.time = time
            return crop
        }
    }
}

// MARK: - Decoding

enum CTCGreedyDecoder {
    /// The text for per-frame best token ids: repeats collapsed, the blank
    /// (first) and end (last) tokens dropped, SentencePiece's "▁" read as a
    /// word start. Lowercased: the model writes capitals.
    static func decode(bestTokens: [Int], tokens: [String]) -> String {
        guard !tokens.isEmpty else { return "" }
        var pieces: [String] = []
        var previous: Int?
        for id in bestTokens {
            defer { previous = id }
            guard id != previous, id != 0, id != tokens.count - 1, tokens.indices.contains(id) else { continue }
            pieces.append(tokens[id])
        }
        return pieces.joined()
            .replacingOccurrences(of: "▁", with: " ")
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }
}

// MARK: - Core ML

/// `@unchecked Sendable`: the loaded model and tokens are guarded by
/// `lock`; predictions run one at a time on `queue`.
final class CoreMLLipReader: LipReading, @unchecked Sendable {
    static let modelName = "LipReader"

    /// ~/Library/Application Support/VocaMac/models/lip-reading/
    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("VocaMac", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("lip-reading", isDirectory: true)
    }

    let directory: URL?
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "com.vocamac.lipreading", qos: .userInitiated)
    private var model: MLModel?
    private var tokens: [String] = []

    init(directory: URL? = CoreMLLipReader.defaultDirectory) {
        self.directory = directory
    }

    private var compiledURL: URL? { directory?.appendingPathComponent("\(Self.modelName).mlmodelc", isDirectory: true) }
    private var packageURL: URL? { directory?.appendingPathComponent("\(Self.modelName).mlpackage", isDirectory: true) }
    private var tokensURL: URL? { directory?.appendingPathComponent("tokens.json") }

    var isInstalled: Bool {
        guard let tokensURL, FileManager.default.fileExists(atPath: tokensURL.path) else { return false }
        return [compiledURL, packageURL].contains { url in url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
    }

    func prepare() async {
        _ = try? await loadedModel()
    }

    func read(_ crops: [MouthCrop]) async throws -> String {
        let (model, tokens) = try await loadedModel()
        let length = crops.count
        guard length >= LipReadingWindow.minimumFrames else { return "" }
        let size = MouthCropGeometry.cropSize
        // MLModel isn't Sendable; this read is its only user on `queue`.
        let box = UncheckedSendableBox(model)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let model = box.value
                do {
                    let input = try MLMultiArray(shape: [1, 1, NSNumber(value: length), NSNumber(value: size), NSNumber(value: size)], dataType: .float32)
                    let pointer = input.dataPointer.bindMemory(to: Float.self, capacity: input.count)
                    let frameSize = size * size
                    for (frame, crop) in crops.enumerated() {
                        for (index, value) in crop.pixels.prefix(frameSize).enumerated() {
                            pointer[frame * frameSize + index] = (Float(value) / 255 - 0.421) / 0.165
                        }
                    }
                    let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["video": input]))
                    guard let logProbs = output.featureValue(for: "log_probs")?.multiArrayValue else {
                        throw LipReadingError.modelFailed("no output")
                    }
                    continuation.resume(returning: CTCGreedyDecoder.decode(bestTokens: Self.bestTokens(logProbs), tokens: tokens))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// The highest-scoring token in each frame of a [1, T, V] output.
    static func bestTokens(_ array: MLMultiArray) -> [Int] {
        let shape = array.shape.map(\.intValue)
        let strides = array.strides.map(\.intValue)
        guard shape.count == 3 else { return [] }
        let frames = shape[1], vocabulary = shape[2]
        var result: [Int] = []
        result.reserveCapacity(frames)
        func best(_ value: (Int) -> Float) {
            for frame in 0..<frames {
                var bestID = 0
                var bestValue = -Float.infinity
                for token in 0..<vocabulary {
                    let candidate = value(frame * strides[1] + token * strides[2])
                    if candidate > bestValue { bestValue = candidate; bestID = token }
                }
                result.append(bestID)
            }
        }
        switch array.dataType {
        case .float16:
            let pointer = array.dataPointer.bindMemory(to: Float16.self, capacity: array.count)
            best { Float(pointer[$0]) }
        case .double:
            let pointer = array.dataPointer.bindMemory(to: Double.self, capacity: array.count)
            best { Float(pointer[$0]) }
        default:
            let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: array.count)
            best { pointer[$0] }
        }
        return result
    }

    // MARK: Loading

    private func loadedModel() async throws -> (MLModel, [String]) {
        if let loaded = lock.withLock({ model.map { ($0, tokens) } }) { return loaded }
        guard isInstalled, let compiledURL, let packageURL, let tokensURL else { throw LipReadingError.notInstalled }
        let started = ProcessInfo.processInfo.systemUptime
        if !FileManager.default.fileExists(atPath: compiledURL.path) {
            // An imported or freshly converted package compiles once.
            let compiled = try await MLModel.compileModel(at: packageURL)
            try? FileManager.default.removeItem(at: compiledURL)
            try FileManager.default.moveItem(at: compiled, to: compiledURL)
        }
        let configuration = MLModelConfiguration()
        // CPU-only and the Neural Engine fail on all but the default length
        // with this export; the GPU runs every length.
        configuration.computeUnits = .cpuAndGPU
        let loaded = try MLModel(contentsOf: compiledURL, configuration: configuration)
        let data = try Data(contentsOf: tokensURL)
        let tokenList = try JSONDecoder().decode([String].self, from: data)
        lock.withLock {
            model = loaded
            tokens = tokenList
        }
        VocaLogger.info(.silentMode, String(format: "Lip-reading model loaded in %.1fs (%d tokens)",
                                            ProcessInfo.processInfo.systemUptime - started, tokenList.count))
        return (loaded, tokenList)
    }

    /// Drop the loaded model (it is about 400 MB).
    func unload() {
        lock.withLock {
            model = nil
            tokens = []
        }
    }

    /// Copy a model folder (LipReader.mlpackage or .mlmodelc, and
    /// tokens.json) into place, replacing what is there.
    func install(from folder: URL) throws {
        guard let directory else { throw LipReadingError.notInstalled }
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        guard names.contains("tokens.json"),
              let modelFile = ["\(Self.modelName).mlmodelc", "\(Self.modelName).mlpackage"].first(where: names.contains) else {
            throw LipReadingError.modelFailed("the folder needs \(Self.modelName).mlpackage and tokens.json")
        }
        unload()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["\(Self.modelName).mlmodelc", "\(Self.modelName).mlpackage", "tokens.json"] {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
        try fileManager.copyItem(at: folder.appendingPathComponent(modelFile), to: directory.appendingPathComponent(modelFile))
        try fileManager.copyItem(at: folder.appendingPathComponent("tokens.json"), to: directory.appendingPathComponent("tokens.json"))
    }

    /// Remove the model from this Mac.
    func remove() throws {
        unload()
        guard let directory, FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}

/// Stands in where no model may be read (tests, headless runs).
final class UnavailableLipReader: LipReading {
    var isInstalled: Bool { false }
    func prepare() async {}
    func read(_ crops: [MouthCrop]) async throws -> String { throw LipReadingError.notInstalled }
    func unload() {}
}
