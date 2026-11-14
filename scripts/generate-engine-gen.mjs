#!/usr/bin/env node
// Generates the engine trees that used to be committed:
//   platforms/web/server/precompute/engine-gen    (bundle engine-rust)
//   platforms/web/client/engine-runtime/engine-gen (bundles ts + protocol-ts)
//
// Both directories are build products and are gitignored. Run the script
// inside `nix develop` (the flake provides the boring driver):
//   node scripts/generate-engine-gen.mjs        # Rust tree
//   node scripts/generate-engine-gen.mjs ts     # JS tree
// The Rust build path runs the first form before `cargo build -p tiqian`;
// the @tiqian/ffi prepack runs the second form before build:runtime.

import { execFileSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const outRoot = join(repoRoot, "engine-haxe", "out");
const target = process.argv[2] ?? "rust";

function runDriver(bundle) {
  try {
    execFileSync("boring", ["gen", bundle, "--project", "boring.json"], {
      cwd: repoRoot,
      stdio: "inherit",
    });
  } catch (error) {
    console.error(
      "generate-engine-gen: the boring driver failed or is missing. " +
        "Run this script inside `nix develop` (the flake provides `boring`).",
    );
    throw error;
  }
}

if (target === "ts") {
  runDriver("ts");
  runDriver("protocol-ts");
  const tsGen = join(outRoot, "ts", "gen");
  const protocolGen = join(outRoot, "protocol-ts", "gen");
  if (!existsSync(tsGen)) {
    throw new Error(`generate-engine-gen: expected driver output at ${tsGen}`);
  }
  if (!existsSync(protocolGen)) {
    throw new Error(`generate-engine-gen: expected driver output at ${protocolGen}`);
  }
  const engineGen = join(repoRoot, "platforms/web/client/engine-runtime/engine-gen");
  rmSync(engineGen, { recursive: true, force: true });
  mkdirSync(engineGen, { recursive: true });
  // The protocol-ts bundle re-emits protocol modules the ts bundle also
  // carries; the ts bundle's copies win because they run the same macros
  // (FontRole's FONT_ROLE_ALL) the protocol bundle does not.
  cpSync(protocolGen, engineGen, { recursive: true });
  cpSync(tsGen, engineGen, { recursive: true });
  const overlay = join(repoRoot, "platforms/web/client/engine-runtime/src/engine-gen-overlay");
  if (existsSync(overlay)) {
    cpSync(overlay, engineGen, { recursive: true });
  }
  console.log(`generate-engine-gen: wrote ${engineGen}`);
} else if (target === "rust") {
  runDriver("engine-rust");
  const generated = join(outRoot, "engine-rust", "gen");
  if (!existsSync(generated)) {
    throw new Error(`generate-engine-gen: expected driver output at ${generated}`);
  }
  const rustGen = join(repoRoot, "platforms/web/server/precompute/engine-gen");
  rmSync(rustGen, { recursive: true, force: true });
  mkdirSync(rustGen, { recursive: true });
  cpSync(generated, rustGen, { recursive: true });
  const tests = join(outRoot, "engine-rust", "gen-tests");
  if (existsSync(tests)) {
    cpSync(tests, rustGen, { recursive: true });
  }
  console.log(`generate-engine-gen: wrote ${rustGen}`);
} else {
  console.error(`generate-engine-gen: unknown target ${target} (expected rust or ts)`);
  process.exit(1);
}
