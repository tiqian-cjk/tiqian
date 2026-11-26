//! Direct Rust consumption of the generated Tiqian layout engine (ADR 0050,
//! Stage1 cutover to the boring engine-rust target).
//!
//! The engine lives in the generated crate `tiqian-engine` (bundle
//! `engine-rust`, sources under engine-haxe/out/engine-rust/gen).
//! The `engine` module adapts it into this crate's error surface and keeps
//! the dependency-injection construction of the engine. The former C ABI
//! layer (packed `LayoutRequest` bytes, `FontBackendVtable`, packed shape
//! buffers, `TIQIAN_NATIVE_LIB_DIR` static linking) is gone; host code
//! passes the generated Rust types directly.
//!
//! Domain validation names (`EmptyParagraph`, `InvalidMaximumMeasure`,
//! `InvalidFontSize`, ...) stay single-sourced in the generated protocol
//! model (platforms/web/server/precompute/protocol-gen,
//! `ParagraphRequestChecks`); the Rust port of the web server wraps them in
//! the `NamedError` type kept below. Byte-protocol error names
//! (`InvalidLayoutRequestMagic`, ...) disappeared together with the packed
//! request encoding.

pub mod engine;

/// A named issue reported to host applications. The web-server Rust port
/// (platforms/web/server/precompute/engine/src/paragraph.rs) and the npm
/// tests assert on these names, so the type and its string payload stay
/// stable.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NamedError(pub String);

impl NamedError {
    pub fn name(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for NamedError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for NamedError {}
