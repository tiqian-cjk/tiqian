#!/usr/bin/env node

import { readFile, readdir, stat } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const EXPECTED_NAME = "@tiqian/prose";
const EXPECTED_VERSION = "0.1.0-alpha.0";
const RUNTIMES = [
  {
    directory: "runtime/",
    path: "runtime/tiqian-web.js",
    marker: "TiqianWeb",
  },
  {
    directory: "precompute-runtime/",
    path: "precompute-runtime/Tiqian-tiqian-web-precompute.mjs",
    marker: "precomputePlainParagraph",
  },
];

function fail(message) {
  throw new Error(`PackageVerificationFailed: ${message}`);
}

export async function verifyPackage(packageRoot = new URL("./", import.meta.url)) {
  const manifest = JSON.parse(await readFile(new URL("package.json", packageRoot), "utf8"));
  if (manifest.name !== EXPECTED_NAME) fail(`expected ${EXPECTED_NAME}, found ${manifest.name}`);
  if (manifest.version !== EXPECTED_VERSION) {
    fail(`expected ${EXPECTED_VERSION}, found ${manifest.version}`);
  }
  if (manifest.license !== "MPL-2.0") fail("manifest must declare MPL-2.0");

  for (const required of ["LICENSE", "README.md"]) {
    const metadata = await stat(new URL(required, packageRoot));
    if (!metadata.isFile() || metadata.size === 0) fail(`${required} is missing or empty`);
    if (!manifest.files.includes(required)) fail(`${required} is absent from files`);
  }
  const [license, readme] = await Promise.all([
    readFile(new URL("LICENSE", packageRoot), "utf8"),
    readFile(new URL("README.md", packageRoot), "utf8"),
  ]);
  if (!license.startsWith("Mozilla Public License Version 2.0")) {
    fail("LICENSE is not the MPL-2.0 text");
  }
  if (!readme.includes(EXPECTED_NAME)) fail(`README.md does not name ${EXPECTED_NAME}`);

  const verified = [];
  for (const runtime of RUNTIMES) {
    if (!manifest.files.includes(runtime.directory)) {
      fail(`${runtime.directory} is absent from files`);
    }
    const source = await readFile(new URL(runtime.path, packageRoot), "utf8");
    if (source.length <= 100 || !source.includes(runtime.marker)) {
      fail(`${runtime.path} is not a non-empty Kotlin/JS runtime`);
    }
    const runtimeEntries = await readdir(new URL(runtime.directory, packageRoot));
    const wasmEntry = runtimeEntries.find((entry) => entry.endsWith(".wasm"));
    if (wasmEntry) {
      fail(`${runtime.directory}${wasmEntry} must not be published`);
    }
    verified.push({ path: runtime.path, size: Buffer.byteLength(source) });
  }
  return verified;
}

const invokedPath = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : null;
if (invokedPath === import.meta.url) {
  const artifacts = await verifyPackage();
  for (const artifact of artifacts) {
    console.log(`verified ${artifact.path} (${artifact.size} bytes)`);
  }
}
