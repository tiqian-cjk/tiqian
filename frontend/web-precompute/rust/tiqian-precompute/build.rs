//! Re-emits the engine-link cfg for this crate. A build script's
//! `cargo:rustc-cfg` applies only to its own crate; values do not flow to
//! dependents. Both this script and the tiqian sys crate's build script read
//! the same TIQIAN_NATIVE_LIB_DIR contract.

use std::env;

fn main() {
    println!("cargo:rerun-if-env-changed=TIQIAN_NATIVE_LIB_DIR");
    if let Some(dir) = env::var("TIQIAN_NATIVE_LIB_DIR")
        .ok()
        .filter(|dir| !dir.is_empty())
    {
        // The engine archive decides whether the engine call exists; a rebuilt
        // archive must recompile this crate too.
        println!("cargo:rerun-if-changed={dir}/libnative.a");
        println!("cargo:rustc-cfg=tiqian_engine_link");
    }
}
