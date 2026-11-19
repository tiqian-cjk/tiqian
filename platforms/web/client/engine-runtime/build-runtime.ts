#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { copyFile, mkdir, rm } from "node:fs/promises";
import { createRequire } from "node:module";
import { fileURLToPath, pathToFileURL } from "node:url";

const require = createRequire(import.meta.url);

// The root postinstall and the package prepare hook pass --install-hook. Those
// hooks run inside `npm install` / `bun install`, where the flake devShell that
// provides the `boring` driver is absent: the three publish workflows install
// without nix. A missing toolchain must not fail the install, because the
// release path regenerates engine-gen/ through `prepack` (build:runtime runs
// before npm test) and a local checkout gets the actionable error from the
// pretest guard (check-engine-gen.ts). Every other invocation, including the
// `build:runtime` script that prepack calls, fails hard instead.
const installHook: boolean = process.argv.includes("--install-hook");

// The Kotlin/JS runtime no longer contributes to the published package:
// since the precompute cutover every capability is served by the generated
// TypeScript tree under engine-gen/. runtime/ is a pure build product, so it
// is wiped directly here instead of routing through a Gradle Sync task that
// configured the whole Kotlin MPP graph (":engine" plus its Android and
// Kotlin/Native targets) only to empty one directory. Dropping the Gradle
// round-trip removes the JDK/Android/Native toolchain requirement from
// build:runtime.
const engineGenDirectory = fileURLToPath(new URL("./engine-gen/", import.meta.url));
if (!existsSync(engineGenDirectory)) {
  const repoRoot = fileURLToPath(new URL("../../../../", import.meta.url));
  const generator = fileURLToPath(new URL("../../../../tools/generate-engine-gen.mjs", import.meta.url));
  const setupScript = fileURLToPath(new URL("../../../../tools/setup-haxe-env.sh", import.meta.url));

  // The boring driver is the generation toolchain, and only the flake devShell
  // provides it. Probe it before staging so an install without nix skips the
  // whole generation step instead of failing at the data-input staging or at
  // the driver call.
  const driver = spawnSync("boring", ["--version"], { stdio: "ignore" });
  if (driver.error) {
    const lines: string[] = [
      "build:runtime: engine-gen/ is missing and the generation toolchain is not on PATH.",
      "  cause: the `boring` driver comes from the flake devShell (`nix develop`).",
      "  next step: nix develop -c npm run build:runtime",
    ];
    if (installHook) {
      console.warn(
        [
          ...lines,
          "  skipped: the install hook continues without engine-gen/ and runtime/;",
          "  the release path regenerates engine-gen/ through `prepack`, and `npm test` reports this same next step.",
        ].join("\n"),
      );
      process.exit(0);
    }
    console.error(
      [
        ...lines,
        "  runtime/ was not rebuilt; @tiqian/ffi has no entry point until the generation succeeds.",
      ].join("\n"),
    );
    process.exit(1);
  }

  // The ts bundle reads tools/unicode-data/; it is gitignored. Stage it from
  // the in-repo source first so a fresh clone needs no manual step.
  console.log("build:runtime: staging the local data inputs for generation");
  const stage = spawnSync("bash", [setupScript], { cwd: repoRoot, stdio: "inherit" });
  if (stage.error || stage.status !== 0) {
    console.error(
      [
        "build:runtime: could not stage the local data inputs.",
        "  cause: " + (stage.error ? stage.error.message : "tools/setup-haxe-env.sh exited with status " + stage.status),
        "  next step: bash tools/setup-haxe-env.sh",
      ].join("\n"),
    );
    process.exit(1);
  }

  console.log("build:runtime: engine-gen/ is missing, generating it from the ts bundles");
  const generate = spawnSync(process.execPath, [generator, "ts"], { cwd: repoRoot, stdio: "inherit" });
  if (generate.error || generate.status !== 0) {
    // The install hook runs this script, so a failed generation must stop the
    // install instead of leaving a package that installs but cannot run.
    const cause = generate.error
      ? generate.error.message
      : "tools/generate-engine-gen.mjs exited with status " + generate.status;
    console.error(
      [
        "build:runtime: engine-gen/ is missing and could not be generated.",
        "  cause: " + cause,
        "  next step: nix develop -c npm run build:runtime",
        "  (the boring driver comes from the flake; tools/setup-haxe-env.sh stages the local data inputs)",
        "  runtime/ was not rebuilt; @tiqian/ffi has no entry point until the generation succeeds.",
      ].join("\n"),
    );
    process.exit(1);
  }
}

const runtimeDirectory = fileURLToPath(new URL("./runtime/", import.meta.url));
await rm(runtimeDirectory, { recursive: true, force: true });
await mkdir(runtimeDirectory, { recursive: true });

// The single-source TypeScript tree under engine-gen/ is compiled with
// rewriteRelativeImportExtensions (P6 precedent: relative .ts specifiers are
// rewritten to .js in the emitted JavaScript), because the generated modules
// import interfaces as value imports, which Node type stripping cannot link.
// npm workspaces hoist typescript to the repository root, so the CLI is
// located through module resolution instead of a fixed relative path.
// Windows resolves the module with backslashes, so name the compiler entry
// through the directory instead of rewriting a POSIX suffix: a path that still
// points at lib/typescript.js runs the library as a script and exits without
// compiling anything.
const typescriptLibrary = require.resolve("typescript/lib/typescript.js");
const typescriptBinary = fileURLToPath(new URL("tsc.js", pathToFileURL(typescriptLibrary)));
const tsc = spawnSync(process.execPath, [typescriptBinary, "-p", "tsconfig.engine-gen.json"], {
  cwd: fileURLToPath(new URL("./", import.meta.url)),
  stdio: "inherit",
});
if (tsc.error) throw tsc.error;
if (tsc.status !== 0) {
  process.exitCode = tsc.status ?? 1;
} else {
  for (const facadeFile of ["facade.mjs", "facade.d.mts", "linebreak-facade.mjs", "clreq-facade.mjs", "font-facade.mjs", "loweringhelper-facade.mjs", "precompute-facade.mjs"]) {
    await copyFile(fileURLToPath(new URL(`./src/${facadeFile}`, import.meta.url)), runtimeDirectory + facadeFile);
  }
}
