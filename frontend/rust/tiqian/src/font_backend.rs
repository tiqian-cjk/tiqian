//! Font backend vtable protocol types (ADR 0050 `PackedFfiCalls`).
//!
//! The layout engine is a Kotlin/Native static library that calls the host
//! font session through the vtable declared in
//! `shaping/api/src/nativeInterop/cinterop/tiqian_font_backend.h`. This module
//! mirrors that header; the two must stay byte-compatible. The engine-side
//! buffer reader and the Rust-side writer in [`crate::shape_buffer`] share the
//! offsets documented there.
//!
//! The `unsafe extern "C" fn` types below are declarations that match the
//! Kotlin-side C function pointer signatures. They mark the callbacks'
//! callability and run nothing by themselves; obligations are listed in
//! docs/rust-unsafe-inventory.md, section "font_backend.rs".

use std::os::raw::c_char;

/// Versions the packed buffer layout and the vtable shape, not the engine.
pub const FONT_BACKEND_PROTOCOL_REVISION: u32 = 1;

/// First four bytes of a shape buffer: "TQPS" in little endian.
pub const SHAPE_BUFFER_MAGIC: u32 = 0x5451_5053;

/// Result codes of `tiqian_install_font_backend`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstallOutcome {
    /// The backend is installed; reinstalling the same revision is a no-op.
    Installed,
    /// A different protocol revision is already installed.
    Collision,
    /// The vtable targets another protocol revision.
    RevisionMismatch,
    /// The vtable pointer was NULL or a callback was missing.
    Invalid,
    /// The engine returned a code outside the documented set; the engine
    /// archive and this crate disagree on the protocol.
    Unknown(i32),
}

impl InstallOutcome {
    pub fn from_code(code: i32) -> Self {
        match code {
            0 => Self::Installed,
            1 => Self::Collision,
            2 => Self::RevisionMismatch,
            3 => Self::Invalid,
            other => Self::Unknown(other),
        }
    }
}

/// One shape callback writes a whole segment as a packed buffer; the contract
/// (capacity probe, at most two calls, named error strings) is documented in
/// the C header.
pub type ShapeFn = unsafe extern "C" fn(
    session_id: *const c_char,
    display_text: *const c_char,
    serialized_families: *const c_char,
    font_size: f64,
    font_weight: i32,
    italic: i32,
    locale: *const c_char,
    role: *const c_char,
    source_text: *const c_char,
    buffer: *mut u8,
    capacity: u64,
    error_out: *mut *mut c_char,
) -> i64;

/// One metrics callback writes five doubles (ascent, descent, leading, typo
/// ascent, typo descent; NaN marks a missing optional metric).
pub type MetricsFn = unsafe extern "C" fn(
    session_id: *const c_char,
    serialized_families: *const c_char,
    font_size: f64,
    font_weight: i32,
    italic: i32,
    role: *const c_char,
    face_selection_text: *const c_char,
    out_metrics: *mut f64,
    error_out: *mut *mut c_char,
) -> i64;

/// Releases a session-owned error string. Accepts NULL.
pub type ReleaseStringFn = unsafe extern "C" fn(string: *const c_char);

/// Host-installed vtable. Field order and types mirror
/// `tiqian_font_backend_vtable_t`; `size` must be `size_of::<FontBackendVtable>()`.
#[repr(C)]
pub struct FontBackendVtable {
    pub size: u32,
    pub protocol_revision: u32,
    pub shape: Option<ShapeFn>,
    pub metrics: Option<MetricsFn>,
    pub release_string: Option<ReleaseStringFn>,
}

impl FontBackendVtable {
    /// A vtable is valid when it carries this protocol revision and all three
    /// callbacks. The engine performs the same checks on install.
    pub fn is_valid(&self) -> bool {
        self.protocol_revision == FONT_BACKEND_PROTOCOL_REVISION
            && self.shape.is_some()
            && self.metrics.is_some()
            && self.release_string.is_some()
    }
}
