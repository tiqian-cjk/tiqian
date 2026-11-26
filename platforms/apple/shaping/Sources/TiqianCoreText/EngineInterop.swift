import TiqianEngine

// Conversions between Swift values and the generated engine's value types. boring's Swift backend
// represents Haxe `String` as UTF-16 code units (`[UInt16]`) and Haxe `Array` as the runtime
// `BoringArray` / `ReadOnlyArray` classes; Apple code converts at these helpers only.

public extension String {
    /// This string's UTF-16 code units, the engine's text representation.
    var engineText: [UInt16] { Array(utf16) }

    /// Decodes engine UTF-16 code units. An unpaired surrogate becomes U+FFFD; offsets that must
    /// stay source-faithful are computed on the code units, never on the decoded string.
    init(engineText: [UInt16]) {
        self = String(decoding: engineText, as: UTF16.self)
    }
}

public extension Array {
    /// A mutable engine array holding a copy of this array.
    var boringArray: BoringArray<Element> { BoringArray(self) }

    /// A read-only engine array holding a copy of this array.
    var readOnlyArray: ReadOnlyArray<Element> { ReadOnlyArray(BoringArray(self)) }
}

public extension ReadOnlyArray {
    /// A Swift array copy of the engine array's elements.
    var array: [Element] { Array(self) }
}
