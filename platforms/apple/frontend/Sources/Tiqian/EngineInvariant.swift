/// `AppleEngineInvariant`: the facade clamps every offset and width before it calls the engine, so
/// an error thrown by the generated engine (`BoringException`) for facade input is a broken
/// invariant, not a recoverable state. The facade stops with the engine's error and the name of the
/// failing call instead of guessing a fallback layout or geometry.
enum EngineInvariant {
    static func call<T>(_ operation: String, _ body: () throws -> T) -> T {
        do {
            return try body()
        } catch {
            preconditionFailure("Tiqian engine call \(operation) failed: \(error)")
        }
    }
}
