//! Session-backed font backend for the engine ABI (ADR 0050 Slice C).
//!
//! The engine consumes fonts exclusively through the vtable protocol. This
//! module presents a [`FontSession`] as that backend and runs one paragraph
//! request through `tiqian_layout_paragraph`. The vtable callbacks are free
//! functions, so the active session and its capture window travel in a
//! thread local; the engine call is synchronous, its callbacks re-enter on
//! the calling thread, and the borrow ends when the call returns. The
//! session id the engine passes back is the id of the lent session and needs
//! no second lookup. Batch paragraphs on worker threads lend their own
//! window, so concurrent engine calls keep their evidence apart.
//!
//! Every `unsafe` in this module sits on the vtable boundary; the obligation
//! list lives in docs/rust-unsafe-inventory.md, section "engine_bridge.rs".

use std::cell::RefCell;
use std::ffi::{c_char, CStr, CString};

use tiqian::font_backend::{FontBackendVtable, InstallOutcome, FONT_BACKEND_PROTOCOL_REVISION};
use tiqian::shape_buffer::{
    required_shape_buffer_size, write_shape_buffer, ShapeEvidence, ShapeGlyphRecord,
};

use crate::paragraph::ParagraphRequest;
use crate::session::{CaptureEvidence, FontSession, MetricsInput, ShapeInput};

/// The session and capture window lent to one engine call.
#[derive(Clone, Copy)]
struct SessionLend {
    session: *const FontSession,
    evidence: *mut CaptureEvidence,
}

thread_local! {
    static CURRENT_LEND: RefCell<Option<SessionLend>> = const { RefCell::new(None) };
}

/// Clears the thread local when the engine call ends, including the panic
/// path.
struct LendSlot;

impl LendSlot {
    fn set(session: &FontSession, evidence: &mut CaptureEvidence) -> Self {
        // unsafe: the thread local stores raw pointers; the borrow rules are
        // held by `precompute_paragraph`, see docs/rust-unsafe-inventory.md.
        CURRENT_LEND.with_borrow_mut(|slot| {
            *slot = Some(SessionLend {
                session: std::ptr::from_ref(session),
                evidence: std::ptr::from_mut(evidence),
            })
        });
        LendSlot
    }
}

impl Drop for LendSlot {
    fn drop(&mut self) {
        CURRENT_LEND.with_borrow_mut(|slot| *slot = None);
    }
}

/// Runs one paragraph request through the engine with `session` and its
/// capture window as the font backend. Both stay borrowed for the duration
/// of the call; nested engine calls on the same thread are not supported.
/// Errors are the named validation issues of the request and the engine.
pub fn precompute_paragraph(
    session: &FontSession,
    evidence: &mut CaptureEvidence,
    request: &ParagraphRequest,
) -> Result<String, String> {
    install_session_backend()?;
    let packed = request
        .to_layout_request()
        .map_err(|error| error.0)?
        .pack()
        .map_err(|error| error.0)?;
    let _slot = LendSlot::set(session, evidence);
    tiqian::engine::layout_paragraph(&packed).map_err(|error| error.0)
}

fn install_session_backend() -> Result<(), String> {
    static VTABLE: std::sync::OnceLock<FontBackendVtable> = std::sync::OnceLock::new();
    static INSTALL: std::sync::OnceLock<Result<(), String>> = std::sync::OnceLock::new();
    INSTALL
        .get_or_init(|| {
            // The struct is a revision field plus three function pointers,
            // so the conversion is total; the error arm keeps the function
            // panic-free.
            let Ok(size) = u32::try_from(std::mem::size_of::<FontBackendVtable>()) else {
                return Err("FontBackendVtableSize".to_string());
            };
            let vtable = VTABLE.get_or_init(|| FontBackendVtable {
                size,
                protocol_revision: FONT_BACKEND_PROTOCOL_REVISION,
                shape: Some(session_shape),
                metrics: Some(session_metrics),
                release_string: Some(session_release_string),
            });
            match tiqian::engine::install_font_backend(vtable) {
                InstallOutcome::Installed => Ok(()),
                outcome => Err(format!("FontBackendInstall{outcome:?}")),
            }
        })
        .clone()
}

/// The lent session and capture window of the running engine call. Both
/// pointers are valid because [`precompute_paragraph`] holds the borrows for
/// the whole call.
fn with_current_lend<T>(call: impl FnOnce(&FontSession, &mut CaptureEvidence) -> T) -> Option<T> {
    let lend = CURRENT_LEND.with_borrow(|slot| *slot)?;
    // SAFETY: the slot is set only inside `precompute_paragraph`, which holds
    // `&FontSession` and `&mut CaptureEvidence` across the engine call, and
    // the engine invokes callbacks on the same call stack. Obligations:
    // docs/rust-unsafe-inventory.md, "engine_bridge.rs".
    Some(call(unsafe { &*lend.session }, unsafe {
        &mut *lend.evidence
    }))
}

/// Reads a C string argument; null maps to `None`, undecodable bytes map to
/// the empty string. The `unsafe` obligation is that callers only pass
/// NUL-terminated engine strings; see docs/rust-unsafe-inventory.md.
unsafe fn c_str<'a>(pointer: *const c_char) -> Option<&'a str> {
    if pointer.is_null() {
        return None;
    }
    // SAFETY: engine arguments are NUL-terminated strings per the ABI.
    Some(unsafe { CStr::from_ptr(pointer) }.to_str().unwrap_or(""))
}

/// Error strings cross the boundary as C strings the engine releases through
/// `release_string`; both ends are this module, so the Rust allocator serves
/// the pair.
fn set_error(error_out: *mut *mut c_char, message: &str) {
    if error_out.is_null() {
        return;
    }
    // The replace strips every NUL byte, so the first conversion succeeds;
    // the fallbacks keep the function total without a panic.
    let cstring = CString::new(message.replace('\0', " "))
        .or_else(|_| CString::new("FontBackendError"))
        .unwrap_or_default();
    // SAFETY: the string crosses to the engine here and returns through
    // `session_release_string`, same allocator on both ends.
    unsafe { *error_out = cstring.into_raw() };
}

// The three callbacks below are the vtable signature the engine invokes;
// the `unsafe` markers are part of that signature. Per-argument decoding and
// buffer writes carry their own comments; obligations:
// docs/rust-unsafe-inventory.md, "engine_bridge.rs".
unsafe extern "C" fn session_shape(
    _session_id: *const c_char,
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
) -> i64 {
    let Some(display_text) = (unsafe { c_str(display_text) }) else {
        set_error(error_out, "FontBackendMissingDisplayText");
        return -1;
    };
    // The `c_str` reads below decode engine arguments per the ABI comment on
    // `c_str`; obligations: docs/rust-unsafe-inventory.md.
    let input = ShapeInput {
        display_text,
        serialized_families: unsafe { c_str(serialized_families) }.unwrap_or(""),
        font_size,
        font_weight: f64::from(font_weight),
        italic: italic != 0,
        locale: unsafe { c_str(locale) }.unwrap_or(""),
        role: unsafe { c_str(role) },
        source_text: unsafe { c_str(source_text) },
    };
    let Some(record) = with_current_lend(|session, evidence| session.shape_into(evidence, &input))
    else {
        set_error(error_out, "FontBackendSessionMissing");
        return -1;
    };
    let record = match record {
        Ok(record) => record,
        Err(message) => {
            set_error(error_out, &message);
            return -1;
        }
    };
    let glyphs: Vec<ShapeGlyphRecord> = record
        .glyphs
        .iter()
        .map(|glyph| ShapeGlyphRecord {
            id: glyph.id,
            advance: glyph.advance,
            x: glyph.x,
            y: glyph.y,
            bounds: glyph.bounds,
        })
        .collect();
    let evidence = ShapeEvidence {
        face_id: record.face_id,
        instance_id: record.font_instance_id,
        script: record.script,
        features: record.features,
        total_advance: record.advance,
        unsafe_break_count: match u32::try_from(record.unsafe_break_count) {
            Ok(count) => count,
            Err(_) => {
                set_error(error_out, "FontBackendUnsafeBreakCountOverflow");
                return -1;
            }
        },
    };
    let needed = required_shape_buffer_size(glyphs.len(), &evidence);
    // The capacity probe compares in u64 and the retry protocol returns the
    // size as i64; both conversions are total for any buffer this process
    // can build, and a violation reports a named error instead of a panic.
    let (Ok(needed_u64), Ok(needed_i64)) = (u64::try_from(needed), i64::try_from(needed)) else {
        set_error(error_out, "FontBackendShapeBufferSizeOverflow");
        return -1;
    };
    if buffer.is_null() || capacity < needed_u64 {
        return needed_i64;
    }
    // SAFETY: the engine passes `capacity` live bytes at `buffer`; the
    // capacity probe above returns `needed` for a single retry.
    let out = unsafe { std::slice::from_raw_parts_mut(buffer, needed) };
    if let Err(error) = write_shape_buffer(out, &glyphs, &evidence) {
        set_error(error_out, &error.0);
        return -1;
    }
    needed_i64
}

// Vtable callback; see the comment above `session_shape`.
unsafe extern "C" fn session_metrics(
    _session_id: *const c_char,
    serialized_families: *const c_char,
    font_size: f64,
    font_weight: i32,
    italic: i32,
    role: *const c_char,
    face_selection_text: *const c_char,
    out_metrics: *mut f64,
    error_out: *mut *mut c_char,
) -> i64 {
    if out_metrics.is_null() {
        return -1;
    }
    // The `c_str` reads below decode engine arguments per the ABI comment on
    // `c_str`; obligations: docs/rust-unsafe-inventory.md.
    let input = MetricsInput {
        serialized_families: unsafe { c_str(serialized_families) }.unwrap_or(""),
        font_size,
        font_weight: f64::from(font_weight),
        italic: italic != 0,
        role: unsafe { c_str(role) },
        face_selection_text: unsafe { c_str(face_selection_text) },
    };
    let Some(values) =
        with_current_lend(|session, evidence| session.metrics_into(evidence, &input))
    else {
        set_error(error_out, "FontBackendSessionMissing");
        return -1;
    };
    let values = match values {
        Ok(values) => values,
        Err(message) => {
            set_error(error_out, &message);
            return -1;
        }
    };
    for (index, value) in values.iter().enumerate() {
        // SAFETY: the engine passes five live doubles at `out_metrics`.
        unsafe { *out_metrics.add(index) = *value };
    }
    0
}

// Vtable callback; see the comment above `session_shape`.
unsafe extern "C" fn session_release_string(string: *const c_char) {
    if string.is_null() {
        return;
    }
    // SAFETY: the pointer came from `CString::into_raw` in `set_error`.
    drop(unsafe { CString::from_raw(string as *mut c_char) });
}
