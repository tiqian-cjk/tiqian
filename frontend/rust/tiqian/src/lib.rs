//! Rust bindings for the Tiqian layout engine's native C ABI (ADR 0050).
//!
//! [`font_backend`] and [`shape_buffer`] carry the font session protocol and
//! its packed buffer encoder as pure Rust. [`layout_request`] packs engine
//! layout requests. [`engine`] holds the `extern` declarations and links only
//! when `TIQIAN_NATIVE_LIB_DIR` points at the Gradle `linkReleaseStatic*`
//! archive of `ffi/native`.

pub mod font_backend;
pub mod layout_request;
pub mod shape_buffer;

#[cfg(tiqian_engine_link)]
pub mod engine;

/// A named issue reported across the C ABI. Domain validation names match the
/// npm test assertions byte for byte (`InvalidMaximumMeasure`, ...); protocol
/// error names match `ffi/native/tiqian_layout_abi.h`.
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
