#!/usr/bin/env node
// Generates the engine trees that used to be committed:
//   platforms/web/server/precompute/engine-gen    (bundle engine-rust)
//   platforms/web/server/precompute/protocol-gen  (bundle protocol-rust)
//
// Both directories are build products and are gitignored. Run the script
// inside `nix develop` (the flake provides the boring driver):
//   node tools/generate-engine-gen.mjs        # Rust tree
// The Rust build path runs this before `cargo build -p tiqian`; the TypeScript
// workspace members are written by `boring pack` instead.

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

if (target === "rust") {
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

  // The protocol crate follows the same shape: `boring gen protocol-rust`
  // writes engine-haxe/out/protocol-rust/gen, and the precompute workspace
  // reads it from this gitignored mount (engine/Cargo.toml points at it).
  runDriver("protocol-rust");
  const protocolGenerated = join(outRoot, "protocol-rust", "gen");
  if (!existsSync(protocolGenerated)) {
    throw new Error(`generate-engine-gen: expected driver output at ${protocolGenerated}`);
  }
  const protocolGen = join(repoRoot, "platforms/web/server/precompute/protocol-gen");
  rmSync(protocolGen, { recursive: true, force: true });
  mkdirSync(protocolGen, { recursive: true });
  cpSync(protocolGenerated, protocolGen, { recursive: true });
  const protocolTests = join(outRoot, "protocol-rust", "gen-tests");
  if (existsSync(protocolTests)) {
    cpSync(protocolTests, protocolGen, { recursive: true });
  }
  console.log(`generate-engine-gen: wrote ${protocolGen}`);
} else {
  console.error(`generate-engine-gen: unknown target ${target} (expected rust or ts)`);
  process.exit(1);
}
