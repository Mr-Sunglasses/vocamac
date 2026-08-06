// LoadSerializer.swift
// VocaMac
//
// Runs async operations one at a time, in the order they were requested.

import Foundation

/// Serializes async work so a second request waits for the first to finish.
///
/// Model loading suspends at several points, so two loads started close
/// together would otherwise interleave and leave two models resident.
actor LoadSerializer {

    /// The most recently queued operation, used to chain the next one behind it.
    private var tail: Task<Void, Never>?

    /// Run `operation` after every operation queued before it has settled.
    ///
    /// A failure in one operation does not prevent later ones from running;
    /// the error is delivered to whoever queued that operation.
    func run(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        let previous = tail

        let task = Task<Result<Void, Error>, Never> {
            await previous?.value
            do {
                try await operation()
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        // Chain the next caller behind this one, discarding the result type so
        // a thrown error cannot cancel the queue.
        tail = Task { _ = await task.value }

        switch await task.value {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
}
