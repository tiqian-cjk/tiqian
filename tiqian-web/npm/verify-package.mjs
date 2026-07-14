#!/usr/bin/env node

import { readFile, stat } from "node:fs/promises";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

const EXPECTED_NAME = "@tiqian/prose";
const EXPECTED_VERSION = "0.1.0-alpha.0";
const WASM_MAGIC = "0061736d";
const RUNTIMES = [
  {
    directory: "runtime/",
    module: "runtime/Tiqian-tiqian-web.mjs",
    path: "runtime/Tiqian-tiqian-web.wasm",
  },
  {
    directory: "precompute-runtime/",
    module: "precompute-runtime/Tiqian-tiqian-web-precompute.mjs",
    path: "precompute-runtime/Tiqian-tiqian-web-precompute.wasm",
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
    const bytes = await readFile(new URL(runtime.path, packageRoot));
    if (bytes.length <= 8 || bytes.subarray(0, 4).toString("hex") !== WASM_MAGIC) {
      fail(`${runtime.path} is not a non-empty WebAssembly module`);
    }
    const moduleSource = await readFile(new URL(runtime.module, packageRoot), "utf8");
    const wasmFileName = runtime.path.slice(runtime.path.lastIndexOf("/") + 1);
    if (!moduleSource.includes(`./${wasmFileName}`)) {
      fail(`${runtime.module} does not reference ${wasmFileName}`);
    }
    verified.push({ path: runtime.path, size: bytes.length });
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
