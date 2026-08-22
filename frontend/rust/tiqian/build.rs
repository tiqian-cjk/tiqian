//! Links the Kotlin/Native engine archive when `TIQIAN_NATIVE_LIB_DIR` points
//! at a Gradle `linkReleaseStatic*` output directory (the one holding
//! libnative.a) and emits the `tiqian_engine_link` cfg. Without the variable
//! the crate stays pure Rust and the engine module is compiled out.

use std::env;

fn main() {
    println!("cargo:rerun-if-env-changed=TIQIAN_NATIVE_LIB_DIR");
    let Some(dir) = env::var("TIQIAN_NATIVE_LIB_DIR")
        .ok()
        .filter(|dir| !dir.is_empty())
    else {
        return;
    };
    // A rebuilt engine archive must relink this crate; the env var alone does
    // not change when the archive changes.
    println!("cargo:rerun-if-changed={dir}/libnative.a");
    println!("cargo:rustc-link-search=native={dir}");
    println!("cargo:rustc-link-lib=static=native");
    // The archive references the system libraries the Kotlin/Native toolchain
    // links its own binaries against on this target, plus the C++ runtime the
    // Kotlin/Native runtime is written against. The NEEDED set of a
    // konan-built test executable plus the unresolved std::thread symbols pin
    // the list.
    if env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("linux") {
        for library in ["m", "pthread", "dl", "gcc_s", "stdc++"] {
            println!("cargo:rustc-link-lib=dylib={library}");
        }
    }
    println!("cargo:rustc-cfg=tiqian_engine_link");
}
