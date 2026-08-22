# Rust unsafe inventory

This document lists every `unsafe` block, function, and trait implementation in
the two Rust workspaces (`frontend/rust`, `frontend/web-precompute/rust`), and
states for each one why it exists and which obligations the caller carries.
Occurrences of the word `unsafe` that are not unsafe code (`unsafe_break_count`
fields, the `unsafeBreakCount` JSON key, the `unsafe_href` function, test
names) are out of scope.

The `unsafe` code sits on two boundaries: the C ABI between the Kotlin engine
archive and Rust (protocol in `ffi/native/tiqian_layout_abi.h`, decision in
ADR 0050), and the shared-library lifecycle boundary between the Neon addon
and the host node process. Code outside these boundaries is safe Rust.

## Obligations shared by both boundaries

- The engine allocates one nativeHeap buffer per `tiqian_layout_paragraph`
  call: the plan buffer on status 0, the error buffer on status 1. Rust
  releases it with `tiqian_release_buffer`. A status of 2 or above marks a
  protocol error; the engine allocated nothing, and Rust must not call
  release.
- Error strings of the font backend move from Rust to the engine through
  `CString::into_raw` and return through the `release_string` callback, which
  takes them back with `CString::from_raw`. Both ends live in this repository,
  so one allocator serves the pair.
- The vtable and its static strings live for the process lifetime; the
  installation never unloads.

## engine.rs: engine call side

File `frontend/rust/tiqian/src/engine.rs`.

| Site | Form | Why it exists |
| --- | --- | --- |
| `ensure_runtime`, inside `call_once` | `libnative_symbols()` | forces the linker to keep the Kotlin/Native runtime symbols, so the runtime is initialized before any engine call |
| `install_font_backend` | `tiqian_install_font_backend(vtable as *const _)` | the C ABI takes a pointer; the vtable is a static and lives for the process lifetime |
| `layout_paragraph` | `tiqian_layout_paragraph(...)` | the call crosses the ABI; the protocol obligations are held by this function |
| status 0 branch | `CStr::from_ptr(plan)` | the engine returns a NUL-terminated UTF-8 buffer per the protocol |
| status 0 branch | `tiqian_release_buffer(plan)` | releases the nativeHeap buffer the engine allocated |
| status 1 branch | `CStr::from_ptr(error)` | the error name is a NUL-terminated string |
| status 1 branch | `tiqian_release_buffer(error)` | releases the error buffer |

Invariants: an empty `request` is rejected before the call; both out-pointers
are set to null before the call; the status decides which buffer to release.
A status outside 0 and 1 releases nothing.

## font_backend.rs: vtable type declarations

File `frontend/rust/tiqian/src/font_backend.rs`. The three
`pub type ... = unsafe extern "C" fn` items declare function pointer types.
They mark the callbacks as callable and run nothing. They must match the C
function pointer signatures the Kotlin side declares.

## engine_bridge.rs: font backend callback side

File `frontend/web-precompute/rust/tiqian-precompute/src/engine_bridge.rs`.
This module hands a `FontSession` to the engine through the vtable.

| Site | Form | Why it exists |
| --- | --- | --- |
| `SessionSlot::set` | `session as *mut FontSession` | the thread local stores a pointer; the borrow rules are held by the call stack of `precompute_paragraph` |
| `with_current_session` | `&mut *pointer` | the callback runs inside the engine call stack, so the `&mut` borrow holds for the call |
| `c_str` function | `unsafe fn` marker | arguments come from the engine; the function maps a null pointer to `None` and bytes that do not decode to the empty string |
| inside `c_str` | `CStr::from_ptr(pointer)` | engine arguments are NUL-terminated strings per the protocol |
| `set_error` | `*error_out = cstring.into_raw()` | hands the error string to the engine, which returns it through `release_string` |
| `session_shape` declaration | `unsafe extern "C" fn` | the vtable callback signature is an unsafe fn type |
| 6 `c_str(...)` calls in `session_shape` | per-argument decoding | see `c_str` |
| buffer write in `session_shape` | `slice::from_raw_parts_mut(buffer, needed)` | the engine passes a buffer with the capacity it reported; when the capacity falls short, the callback returns the size it needs and the engine retries |
| `session_metrics` declaration | `unsafe extern "C" fn` | see `session_shape` |
| 3 `c_str(...)` calls in `session_metrics` | per-argument decoding | see `c_str` |
| write in `session_metrics` | `*out_metrics.add(index) = *value` | the engine passes an out-buffer of five doubles |
| `session_release_string` declaration | `unsafe extern "C" fn` | see `session_shape` |
| inside `session_release_string` | `CString::from_raw(string)` | takes back the string `set_error` handed out; both ends use one allocator |

Invariants: the session pointer is valid only inside the call stack of
`precompute_paragraph`; `SessionSlot` clears the thread local on the panic
path as well. The shape callback follows the retry protocol: it returns the
size it needs when the capacity falls short, the engine retries once, and a
second shortfall reports `FontBackendBufferOverflow`.

## pin.rs: AddonMappingPin

File `frontend/web-precompute/rust/tiqian-precompute-neon/src/pin.rs`.

Background: node calls `dlclose` on every addon an environment loaded when
that environment is destroyed, which happens when a worker thread exits. An
engine call attaches the Kotlin/Native runtime to the calling thread and
registers thread-local destructors inside this library; the runtime also
starts its GC threads, which belong to the process. After the unmap, those
destructors and threads point at unmapped code, and `__nptl_deallocate_tsd`
raises SIGSEGV during worker teardown. The vite SSR worker pool reproduces
this crash: the build succeeds, and the process crashes on exit.

| Site | Form | Why it exists |
| --- | --- | --- |
| `pin_once` / `pin` on unix | `dladdr`, `dlopen` declarations and calls | `dladdr` locates the shared library that contains this function; `dlopen` on a file that is already loaded raises the reference count and marks the library NODELETE without running initializers again |
| `pin` on windows | `GetModuleHandleExW` declaration and call | the PIN flag ties the DLL to the process lifetime, so a later `FreeLibrary` does not unload it |

Invariants: `pin_once` runs once, at the addon registration entry; the handle
from `dlopen` is never closed and holds the reference for the process
lifetime; a failed call leaves the library unpinned, which matches the
behavior before the fix. The unix path is verified against this crash; the
windows and arm64 paths compile, and no run in this repository exercises them.

## plan_parity.rs: test fixture backend

File `frontend/web-precompute/rust/tiqian-precompute/tests/plan_parity.rs`.
The test runs a deterministic font backend over the same C ABI and compares
its plan dump with the js oracle byte for byte. Its `unsafe` sites mirror
`engine_bridge.rs`: the three callback declarations `fixture_shape`,
`fixture_metrics`, `fixture_release_string`; `CStr::from_ptr` for argument
decoding; `from_raw_parts_mut` for the shape buffer write;
`*out_metrics.add` for the metrics out-buffer. The test passes through the
same boundary as the production callbacks, so the protocol obligations are
the same.

## Residual risk

- A Rust panic that unwinds through a C callback into Kotlin frames is
  undefined behavior. The panic sources inside the callbacks are allocation
  failure and the `unwrap_or` fallbacks; session callbacks report every error
  through the error code path.
- Leak paths: the plan and error buffers are released in pairs, and the
  error strings change hands in pairs. No leak path across the boundary is
  known.
- The registry of `tiqian-precompute-neon` keeps its entries addressable
  after close. This is not unsafe code and not a leak; memory grows when a
  process creates precomputers in a loop. This is a trade-off.
