// FileDownloader.swift
// VocaMac
//
// Minimal file downloader with real progress reporting, used for model
// archives that engines don't download themselves (sherpa-onnx).

import Foundation

enum FileDownloaderError: LocalizedError {
    case badResponse(statusCode: Int)
    case moveFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .badResponse(let statusCode):
            return "Server returned HTTP \(statusCode)."
        case .moveFailed(let reason):
            return "Could not store the downloaded file: \(reason)"
        }
    }
}

/// Downloads a URL to a destination file, reporting fractional progress.
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private let destination: URL
    private let onProgress: (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?

    private init(destination: URL, onProgress: @escaping (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    /// Download `url` to `destination`, overwriting any existing file.
    /// - Parameter onProgress: Called with values in 0...1. Invoked on a
    ///   background queue; hop to the main actor for UI updates.
    static func download(
        from url: URL,
        to destination: URL,
        onProgress: @escaping (Double) -> Void = { _ in }
    ) async throws {
        let downloader = FileDownloader(destination: destination, onProgress: onProgress)
        let session = URLSession(
            configuration: .default,
            delegate: downloader,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            downloader.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            finish(with: FileDownloaderError.badResponse(statusCode: response.statusCode))
            return
        }

        do {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: location, to: destination)
            finish(with: nil)
        } catch {
            finish(with: FileDownloaderError.moveFailed(reason: error.localizedDescription))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            finish(with: error)
        }
    }

    private func finish(with error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
