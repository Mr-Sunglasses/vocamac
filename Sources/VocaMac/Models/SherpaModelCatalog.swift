// SherpaModelCatalog.swift
// VocaMac
//
// Registry of the specialized ONNX models served by the sherpa-onnx engine:
// where each model's archive lives, what files it contains, and which
// sherpa-onnx recognizer configuration it needs.

import Foundation

/// Describes one downloadable sherpa-onnx model.
struct SherpaModelSpec {

    /// Which recognizer configuration the model uses, with file names
    /// relative to the extracted model directory.
    enum Kind {
        /// Moonshine v2 (encoder + merged decoder, .ort format)
        case moonshine(encoder: String, mergedDecoder: String)
        /// SenseVoice (single model file)
        case senseVoice(model: String)
        /// NeMo CTC models such as GigaAM (single model file)
        case nemoCtc(model: String)
        /// NVIDIA Canary (encoder + decoder, with a fixed language set)
        case canary(encoder: String, decoder: String, supportedLanguages: Set<String>)
    }

    /// The catalog entry this spec belongs to
    let size: ModelSize

    /// Download URL of the .tar.bz2 archive
    let archiveURL: URL

    /// Name of the top-level directory inside the archive
    let directoryName: String

    /// Recognizer configuration details
    let kind: Kind

    /// Token table file, relative to the model directory
    let tokensFile = "tokens.txt"

    /// All files that must exist for the model to count as downloaded,
    /// relative to the model directory.
    var requiredFiles: [String] {
        switch kind {
        case .moonshine(let encoder, let mergedDecoder):
            return [tokensFile, encoder, mergedDecoder]
        case .senseVoice(let model), .nemoCtc(let model):
            return [tokensFile, model]
        case .canary(let encoder, let decoder, _):
            return [tokensFile, encoder, decoder]
        }
    }
}

/// All sherpa-onnx models VocaMac offers.
enum SherpaModelCatalog {

    private static let releaseBase =
        "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/"

    private static func spec(
        _ size: ModelSize,
        directory: String,
        kind: SherpaModelSpec.Kind
    ) -> SherpaModelSpec {
        SherpaModelSpec(
            size: size,
            archiveURL: URL(string: releaseBase + directory + ".tar.bz2")!,
            directoryName: directory,
            kind: kind
        )
    }

    static let specs: [SherpaModelSpec] = [
        spec(
            .moonshineTiny,
            directory: "sherpa-onnx-moonshine-tiny-en-quantized-2026-02-27",
            kind: .moonshine(
                encoder: "encoder_model.ort",
                mergedDecoder: "decoder_model_merged.ort"
            )
        ),
        spec(
            .moonshineBase,
            directory: "sherpa-onnx-moonshine-base-en-quantized-2026-02-27",
            kind: .moonshine(
                encoder: "encoder_model.ort",
                mergedDecoder: "decoder_model_merged.ort"
            )
        ),
        spec(
            .senseVoiceSmall,
            directory: "sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2025-09-09",
            kind: .senseVoice(model: "model.int8.onnx")
        ),
        spec(
            .gigaamV3,
            directory: "sherpa-onnx-nemo-ctc-punct-giga-am-v3-russian-2025-12-16",
            kind: .nemoCtc(model: "model.int8.onnx")
        ),
        spec(
            .canary180mFlash,
            directory: "sherpa-onnx-nemo-canary-180m-flash-en-es-de-fr-int8",
            kind: .canary(
                encoder: "encoder.int8.onnx",
                decoder: "decoder.int8.onnx",
                supportedLanguages: ["en", "es", "de", "fr"]
            )
        ),
    ]

    /// Look up the spec for a catalog entry, if it is a sherpa-onnx model.
    static func spec(for size: ModelSize) -> SherpaModelSpec? {
        specs.first { $0.size == size }
    }
}
