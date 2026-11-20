#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { copyFile, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot: string = fileURLToPath(new URL("./", import.meta.url));
const consumerRoot: string = await mkdtemp(resolve(tmpdir(), "tiqian-ffi-release-"));
let tarballPath: string | null = null;

interface RunNpmOptions {
  readonly cwd?: string;
  readonly capture?: boolean;
}

function runNpm(arguments_: readonly string[], options: RunNpmOptions = {}): string {
  const npmCli: string | undefined = process.env.npm_execpath;
  const command: string = npmCli ? process.execPath : process.platform === "win32" ? "npm.cmd" : "npm";
  const args: readonly string[] = npmCli ? [npmCli, ...arguments_] : arguments_;
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? packageRoot,
    encoding: "utf8",
    stdio: options.capture ? "pipe" : "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const detail: string = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
    throw new Error(`ReleaseConsumerCommandFailed: npm ${arguments_.join(" ")}\n${detail}`);
  }
  return result.stdout ?? "";
}

interface PackedItem {
  readonly filename?: string;
}

type PackedList = readonly PackedItem[];

try {
  // prepack already rebuilt and verified the working tree. Pack without scripts
  // here so this consumer check cannot recursively invoke verify:release.
  const packed: PackedList = JSON.parse(runNpm([
    "pack",
    "--ignore-scripts",
    "--json",
    "--pack-destination",
    consumerRoot,
  ], { capture: true })) as PackedList;
  const filename: string | undefined = packed?.[0]?.filename;
  if (!filename) throw new Error("ReleaseConsumerPackFailed: npm pack returned no filename");
  tarballPath = resolve(consumerRoot, filename);

  await writeFile(
    resolve(consumerRoot, "package.json"),
    `${JSON.stringify({ private: true, type: "module" }, null, 2)}\n`,
  );
  runNpm([
    "install",
    "--ignore-scripts",
    "--package-lock=false",
    "--no-audit",
    "--no-fund",
    tarballPath,
  ], { cwd: consumerRoot });

  await writeFile(
    resolve(consumerRoot, "verify.mjs"),
    `import assert from "node:assert/strict";
import * as ffi from "@tiqian/ffi";

assert.equal(typeof ffi.precomputeParagraphWithDiagnostics, "function");
assert.equal(typeof ffi.precomputeParagraphWithBrowserMetrics, "function");
assert.match(import.meta.resolve("@tiqian/ffi"), /facade\\.mjs$/u);
`,
  );
  const result = spawnSync(process.execPath, ["verify.mjs"], {
    cwd: consumerRoot,
    encoding: "utf8",
    stdio: "pipe",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const detail: string = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
    throw new Error(`ReleaseConsumerImportFailed:\n${detail}`);
  }
  console.log("verified packed @tiqian/ffi exports in an isolated consumer");
  const artifactDirectory: string = String(process.env.TIQIAN_RELEASE_ARTIFACT_DIR ?? "").trim();
  if (artifactDirectory) {
    const outputDirectory: string = resolve(artifactDirectory);
    await mkdir(outputDirectory, { recursive: true });
    const outputPath: string = resolve(outputDirectory, filename);
    await copyFile(tarballPath, outputPath);
    console.log(`retained verified release tarball at ${outputPath}`);
  }
} finally {
  await rm(consumerRoot, { force: true, recursive: true });
}
