#!/usr/bin/env bash
# Runs the two precision rounds of the generated Rust engine over one tree.
#
# Round 1 is the default configuration. Round 2 selects the f32 cargo feature
# on the same generated sources, so f32 needs neither a second generation entry
# nor a second bundle. The generated tree comes from
# node scripts/generate-engine-gen.mjs (bundle engine-rust); pass the crate
# directory as the first argument (default: the bundle output).
#
# The Rust target harness is serial (Plan.hx pins --test-threads=1, and
# RustStaticRealization.hx defaults to the serial harness). Parallel execution
# is not a supported mode: the shared static caches in PlanJsonNumber are read
# and rewritten by concurrent tests.
set -euo pipefail

export BORING_TEST_TIMEOUT_MS=600000

if [ "$#" -ge 1 ]; then
  crate="$1"
else
  crate=engine-haxe/out/engine-rust/gen
fi

cargo test --manifest-path "$crate/Cargo.toml" -- --test-threads=1
cargo test --manifest-path "$crate/Cargo.toml" --features f32 -- --test-threads=1
