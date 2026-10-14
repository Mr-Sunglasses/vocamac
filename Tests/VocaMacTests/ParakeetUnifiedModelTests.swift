// ParakeetUnifiedModelTests.swift
// VocaMac
//
// Catalog, file, and routing checks for Parakeet Unified 0.6B. None of these
// download or load the model.

import XCTest
import FluidAudio
@testable import VocaMac

final class ParakeetUnifiedModelTests: XCTestCase {

    func testCatalogEntry() {
        let unified = ModelSize.parakeetUnified
        XCTAssertEqual(unified.engine, .parakeet)
        XCTAssertEqual(unified.displayName, "Parakeet Unified (English)")
        XCTAssertEqual(unified.creator, .nvidia)
        XCTAssertEqual(unified.languageCoverage, .only(["en"]))
        XCTAssertFalse(unified.translatesToEnglish)
        XCTAssertFalse(unified.isSystemManaged)
        XCTAssertFalse(unified.bindsLanguageAtLoadTime)
        XCTAssertEqual(unified.relativeSpeed, 1)
        XCTAssertEqual(unified.qualityDescription, "Excellent")
        XCTAssertFalse(unified.pickerSummary.isEmpty)
    }

    /// The installed size is the batch export only (int8 encoder, decoder,
    /// joint, vocab), as listed in FluidInference/parakeet-unified-en-0.6b-coreml.
    func testSizeAndMemoryEstimate() {
        let unified = ModelSize.parakeetUnified
        XCTAssertEqual(unified.fileSizeBytes, 614_080_920)
        XCTAssertEqual(unified.ramRequiredGB, ModelRAMFit.parakeetLoaded.estimateGB(fileSizeBytes: unified.fileSizeBytes))
        XCTAssertGreaterThanOrEqual(unified.ramRequiredGB, ModelSize.parakeetV2.ramRequiredGB)
        XCTAssertLessThanOrEqual(unified.ramRequiredGB, ModelSize.parakeetUltra.ramRequiredGB)
        XCTAssertEqual(unified.firstLoadRAMRequiredGB, unified.ramRequiredGB)
    }

    func testRatedBetweenParakeetV2AndUltra() {
        XCTAssertGreaterThan(ModelSize.parakeetUnified.accuracyScore, ModelSize.parakeetV2.accuracyScore)
        XCTAssertLessThan(ModelSize.parakeetUnified.accuracyScore, ModelSize.parakeetUltra.accuracyScore)
        XCTAssertEqual(ModelSize.parakeetUnified.speedScore, ModelSize.parakeetV2.speedScore)
    }

    func testListedInThePickerWithTheOtherParakeetModels() throws {
        let catalog = ModelSize.standardCatalog
        let index = try XCTUnwrap(catalog.firstIndex(of: .parakeetUnified))
        XCTAssertEqual(catalog[index + 1], .parakeetV2)
        XCTAssertEqual(catalog.first, .parakeetUltra, "Ultra stays first")
    }

    func testRoutedToTheUnifiedPipeline() {
        XCTAssertEqual(ParakeetService.family(for: .parakeetUnified), .unified)
        XCTAssertEqual(ParakeetService.family(for: .parakeetV2), .tdt(.v2))
        XCTAssertNil(ParakeetService.family(for: .tiny))
        XCTAssertEqual(TranscriptionRouter.engine(forModelIdentifier: "parakeet-unified-en-0.6b"), .parakeet)
        XCTAssertTrue(ParakeetService.writesNumbers(.parakeetUnified))
        XCTAssertFalse(ParakeetService.writesNumbers(.parakeetV3))
    }

    func testFilesLiveInFluidAudiosCacheForItsRepository() {
        XCTAssertEqual(ParakeetUnifiedModel.directory.lastPathComponent, Repo.parakeetUnified.folderName)
        XCTAssertEqual(ParakeetUnifiedModel.directory.deletingLastPathComponent(), ParakeetUnifiedModel.modelsRoot)
        XCTAssertEqual(ParakeetService.modelDirectory(for: .parakeetUnified), ParakeetUnifiedModel.directory)
        XCTAssertTrue(ParakeetService.modelDirectories.contains(ParakeetUnifiedModel.directory))
        XCTAssertEqual(ParakeetUnifiedModel.requiredFiles, [
            "parakeet_unified_encoder_int8.mlmodelc",
            "parakeet_unified_decoder.mlmodelc",
            "parakeet_unified_joint_decision_single_step.mlmodelc",
            "vocab.json",
        ])
        XCTAssertEqual(ParakeetUnifiedModel.encoderPrecision, .int8)
    }

    func testModelsExistOnlyWithEveryFileAndAProgram() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParakeetUnifiedModelTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        XCTAssertFalse(ParakeetUnifiedModel.modelsExist(at: directory))

        for file in ParakeetUnifiedModel.requiredFiles {
            let url = directory.appendingPathComponent(file)
            if url.pathExtension == "mlmodelc" {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try Data().write(to: url.appendingPathComponent("coremldata.bin"))
            } else {
                try Data("{}".utf8).write(to: url)
            }
        }
        XCTAssertFalse(ParakeetUnifiedModel.modelsExist(at: directory), "A bundle without its program is incomplete")

        for file in ParakeetUnifiedModel.requiredFiles where file.hasSuffix(".mlmodelc") {
            try Data().write(to: directory.appendingPathComponent(file).appendingPathComponent("model.mil"))
        }
        XCTAssertTrue(ParakeetUnifiedModel.modelsExist(at: directory))
    }

    func testDownloadSizeAllowsForTheInstall() {
        XCTAssertGreaterThan(
            ModelManager.requiredDownloadBytes(for: .parakeetUnified), ModelSize.parakeetUnified.fileSizeBytes
        )
    }
}
