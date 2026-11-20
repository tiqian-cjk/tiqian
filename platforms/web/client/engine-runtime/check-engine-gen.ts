#!/usr/bin/env node

// pretest guard: tsc -b resolves `@tiqian/ffi` through runtime/facade.d.mts,
// which build:runtime compiles from engine-gen/. When the install hook skipped
// the generation (no flake devShell), tsc reports only
// `TS2307: Cannot find module '@tiqian/ffi'`, which names neither the cause nor
// the fix. Fail here first with the command that produces engine-gen/.
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

const engineGenDirectory: string = fileURLToPath(new URL("./engine-gen/", import.meta.url));
const runtimeDirectory: string = fileURLToPath(new URL("./runtime/", import.meta.url));

if (!existsSync(engineGenDirectory)) {
  console.error(
    [
      "pretest: engine-gen/ is missing, so tsc cannot resolve @tiqian/ffi.",
      "  next step: nix develop -c npm run build:runtime",
      "  (build:runtime generates engine-gen/ with the flake's boring driver, then compiles runtime/ from it)",
    ].join("\n"),
  );
  process.exit(1);
}

if (!existsSync(runtimeDirectory)) {
  console.error(
    [
      "pretest: runtime/ is missing, so tsc cannot resolve @tiqian/ffi.",
      "  next step: npm run build:runtime",
      "  (build:runtime compiles runtime/ from the existing engine-gen/)",
    ].join("\n"),
  );
  process.exit(1);
}
