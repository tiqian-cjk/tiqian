//! AddonMappingPin: keeps this addon mapped for the process lifetime.
//!
//! Node dlcloses every addon an environment loaded when that environment is
//! destroyed, which happens when a worker thread exits. Engine calls attach
//! the Kotlin/Native runtime to the calling thread and register thread-local
//! destructors inside this library. The runtime GC threads are also process
//! wide. Unmapping the library leaves those destructors and threads pointing
//! at unmapped code, which segfaults at worker teardown. The addon therefore
//! never unloads. The unsafe obligations are listed in
//! docs/rust-unsafe-inventory.md.

use std::ffi::c_int;
use std::sync::Once;

static PIN: Once = Once::new();

// RTLD constant values differ per unix platform. They are spelled out here
// so the values stay auditable.
#[cfg(all(unix, target_os = "macos"))]
const RTLD_LAZY: c_int = 0x0001;
#[cfg(all(unix, target_os = "macos"))]
const RTLD_NODELETE: c_int = 0x0080;
#[cfg(all(unix, not(target_os = "macos")))]
const RTLD_LAZY: c_int = 0x0001;
#[cfg(all(unix, not(target_os = "macos")))]
const RTLD_NODELETE: c_int = 0x1000;

#[cfg(unix)]
#[repr(C)]
struct DlInfo {
    dli_fname: *const std::ffi::c_char,
    dli_fbase: *mut core::ffi::c_void,
    dli_sname: *const std::ffi::c_char,
    dli_saddr: *mut core::ffi::c_void,
}

#[cfg(unix)]
unsafe extern "C" {
    fn dladdr(address: *const core::ffi::c_void, info: *mut DlInfo) -> c_int;
    fn dlopen(filename: *const std::ffi::c_char, flags: c_int) -> *mut core::ffi::c_void;
}

#[cfg(windows)]
unsafe extern "C" {
    fn GetModuleHandleExW(
        flags: u32,
        address: *const core::ffi::c_void,
        module: *mut *mut core::ffi::c_void,
    ) -> i32;
}

#[cfg(windows)]
const GET_MODULE_HANDLE_EX_FLAG_PIN: u32 = 0x00000001;
#[cfg(windows)]
const GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS: u32 = 0x00000004;

/// Called once from the addon registration entry point. After success, node's
/// dlclose can no longer unmap this library. On failure the previous behavior
/// stands and no error is raised.
pub fn pin_once() {
    PIN.call_once(pin);
}

// A static in this module anchors the library lookup: dladdr and
// GetModuleHandleExW accept any address inside the module's mapping.
static ANCHOR: u8 = 0;

fn anchor_address() -> *const core::ffi::c_void {
    std::ptr::from_ref(&ANCHOR).cast::<core::ffi::c_void>()
}

#[cfg(unix)]
fn pin() {
    // unsafe boundary and obligations: see the AddonMappingPin section in
    // docs/rust-unsafe-inventory.md. dladdr locates the shared library that
    // contains this function. dlopen on an already loaded file only bumps the
    // reference count and marks it NODELETE, and does not rerun initializers.
    // The returned handle is never closed.
    unsafe {
        let mut info = DlInfo {
            dli_fname: std::ptr::null(),
            dli_fbase: std::ptr::null_mut(),
            dli_sname: std::ptr::null(),
            dli_saddr: std::ptr::null_mut(),
        };
        if dladdr(anchor_address(), &mut info) == 0 {
            return;
        }
        if info.dli_fname.is_null() {
            return;
        }
        dlopen(info.dli_fname, RTLD_LAZY | RTLD_NODELETE);
    }
}

#[cfg(windows)]
fn pin() {
    // unsafe boundary and obligations: see the AddonMappingPin section in
    // docs/rust-unsafe-inventory.md. The PIN flag ties the DLL to the process
    // lifetime, so a later FreeLibrary does not unload it.
    unsafe {
        let mut module: *mut core::ffi::c_void = std::ptr::null_mut();
        GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_PIN | GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
            anchor_address(),
            &mut module,
        );
    }
}
