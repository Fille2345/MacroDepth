// Support/AsyncBroadcaster.swift

import Foundation
import os

/// Fan-out of values to any number of `AsyncStream` subscribers, replaying the
/// latest value to each new subscriber.
///
/// Used to bridge callback-based producers (e.g. `ARSessionDelegate`, which is
/// called on an arbitrary queue) into Swift Concurrency without Combine.
/// Thread-safe via `OSAllocatedUnfairLock`, so `send` may be called from any thread.
final class AsyncBroadcaster<Element: Sendable>: Sendable {
    private struct State: Sendable {
        var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
        var latest: Element?
        var isFinished = false
    }

    private let state: OSAllocatedUnfairLock<State>
    private let bufferSize: Int

    init(initialValue: Element? = nil, bufferSize: Int = 16) {
        state = OSAllocatedUnfairLock(initialState: State(latest: initialValue))
        self.bufferSize = bufferSize
    }

    var latest: Element? {
        state.withLock { $0.latest }
    }

    /// A new stream that first yields the latest value (if any), then every
    /// subsequent value. It ends when the consumer is cancelled or `finish()` is called.
    func stream() -> AsyncStream<Element> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: Element.self,
            bufferingPolicy: .bufferingNewest(bufferSize)
        )
        continuation.onTermination = { [weak self] _ in
            self?.removeContinuation(id: id)
        }

        // Yield the replay value inside the lock so a concurrent `send` cannot
        // deliver a newer value before the older replayed one.
        let registered = state.withLock { state -> Bool in
            guard !state.isFinished else { return false }
            state.continuations[id] = continuation
            if let latest = state.latest {
                continuation.yield(latest)
            }
            return true
        }
        if !registered {
            continuation.finish()
        }
        return stream
    }

    func send(_ element: Element) {
        state.withLock { state in
            guard !state.isFinished else { return }
            state.latest = element
            for continuation in state.continuations.values {
                continuation.yield(element)
            }
        }
    }

    func finish() {
        // Finish outside the lock: `finish()` triggers `onTermination`, which takes the lock.
        let continuations = state.withLock { state -> [AsyncStream<Element>.Continuation] in
            state.isFinished = true
            let current = Array(state.continuations.values)
            state.continuations.removeAll()
            return current
        }
        continuations.forEach { $0.finish() }
    }

    private func removeContinuation(id: UUID) {
        state.withLock { state in
            _ = state.continuations.removeValue(forKey: id)
        }
    }
}
