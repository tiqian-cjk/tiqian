#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { copyFile, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const packageRoot = fileURLToPath(new URL("./", import.meta.url));
const consumerRoot = await mkdtemp(resolve(tmpdir(), "tiqian-prose-release-"));
let tarballPath = null;

function runNpm(arguments_, options = {}) {
  const npmCli = process.env.npm_execpath;
  const command = npmCli ? process.execPath : process.platform === "win32" ? "npm.cmd" : "npm";
  const args = npmCli ? [npmCli, ...arguments_] : arguments_;
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? packageRoot,
    encoding: "utf8",
    stdio: options.capture ? "pipe" : "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const detail = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
    throw new Error(`ReleaseConsumerCommandFailed: npm ${arguments_.join(" ")}\n${detail}`);
  }
  return result.stdout ?? "";
}

try {
  // prepack already rebuilt and verified the working tree. Pack without scripts
  // here so this consumer check cannot recursively invoke verify:release.
  const packed = JSON.parse(runNpm([
    "pack",
    "--ignore-scripts",
    "--json",
    "--pack-destination",
    consumerRoot,
  ], { capture: true }));
  const filename = packed?.[0]?.filename;
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
import * as api from "@tiqian/prose";
import { TiqianProseElement } from "@tiqian/prose/element";
import * as precompute from "@tiqian/prose/precompute";

assert.equal(typeof api.enhance, "function");
assert.equal(typeof api.destroy, "function");
assert.equal(typeof TiqianProseElement, "function");
assert.deepEqual(Object.keys(precompute).sort(), [
  "createPrecomputer",
  "renderFontContractBundle",
  "renderPreparedParagraph",
  "renderSnapshotBundle",
  "renderSnapshotTemplate",
  "snapshotPlainTextIssue",
]);
assert.match(import.meta.resolve("@tiqian/prose/styles.css"), /styles\\.css$/u);
`,
  );
  const result = spawnSync(process.execPath, ["verify.mjs"], {
    cwd: consumerRoot,
    encoding: "utf8",
    stdio: "pipe",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const detail = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
    throw new Error(`ReleaseConsumerImportFailed:\n${detail}`);
  }
  console.log("verified packed @tiqian/prose exports in an isolated consumer");
  const artifactDirectory = String(process.env.TIQIAN_RELEASE_ARTIFACT_DIR ?? "").trim();
  if (artifactDirectory) {
    const outputDirectory = resolve(artifactDirectory);
    await mkdir(outputDirectory, { recursive: true });
    const outputPath = resolve(outputDirectory, filename);
    await copyFile(tarballPath, outputPath);
    console.log(`retained verified release tarball at ${outputPath}`);
  }
} finally {
  await rm(consumerRoot, { force: true, recursive: true });
}
