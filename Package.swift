// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift Package Manager required to build this package.

import PackageDescription

let package = Package(
    name: "VocaMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "VocaMac",
            targets: ["VocaMac"]
        )
    ],
    dependencies: [
        // WhisperKit — local, on-device speech-to-text powered by CoreML
        // https://github.com/argmaxinc/WhisperKit
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.4"),
        // FluidAudio — NVIDIA Parakeet TDT models as CoreML on the Neural Engine
        // https://github.com/FluidInference/FluidAudio
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
        // sherpa-onnx — specialized ONNX models (Moonshine, SenseVoice,
        // GigaAM, Canary) via ONNX Runtime, CPU-only.
        // Pinned to a revision: the SPM manifest is not in a tagged release
        // yet; the pinned manifest references the v1.13.4 binary xcframework.
        .package(
            url: "https://github.com/k2-fsa/sherpa-onnx",
            revision: "00ad9a19a63751a6c4b12050a00eacfeb204814e"
        ),
    ],
    targets: [
        // Objective-C helpers used by the Swift app.
        .target(
            name: "VocaMacObjC",
            path: "Sources/VocaMacObjC",
            publicHeadersPath: "include"
        ),
        // Main application target
        .executableTarget(
            name: "VocaMac",
            dependencies: [
                "VocaMacObjC",
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "sherpa-onnx", package: "sherpa-onnx"),
            ],
            path: "Sources/VocaMac",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        // Test target
        .testTarget(
            name: "VocaMacTests",
            dependencies: ["VocaMac"],
            path: "Tests/VocaMacTests"
        )
    ]
)
