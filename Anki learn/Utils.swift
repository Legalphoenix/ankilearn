import Foundation

// MARK: - Concurrency Helpers

/// Retries an async, throwing operation a specified number of times.
func retry<T>(times: Int, delay: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    for attempt in 0..<times {
        do {
            return try await operation()
        } catch {
            // If this was the last attempt, rethrow the error
            if attempt == times - 1 {
                throw error
            }
            // Wait for the specified delay before retrying
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
    // This should not be reachable, but is required for the compiler.
    // The loop will always either return or throw.
    fatalError("Retry loop finished without returning or throwing.")
}

extension Array {
    /// Splits the array into chunks of a given size.
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
