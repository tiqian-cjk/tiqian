#!/usr/bin/env node

import { readFile, stat } from "node:fs/promises";
import type { Stats } from "node:fs";
import { resolve } from "node:path";
import { pathToFileURL } from "node:url";

import { normalizeReleaseVersion } from "./prepare-release.js";

export interface VerifiedArtifact {
  readonly path: string;
  readonly size: number;
}

interface PackageManifest {
  readonly name: string;
  readonly version: string;
  readonly license?: string;
  readonly files: readonly string[];
  readonly dependencies?: Readonly<Record<string, string>>;
  readonly exports?: Readonly<Record<string, unknown>>;
}

const EXPECTED_NAME: string = "@tiqian/web-component";
const REQUIRED_FILES: readonly string[] = [
  "LICENSE",
  "README.md",
  "auto.d.ts",
  "auto.js",
  "element.d.ts",
  "element.js",
  "prepared-dom.d.ts",
  "prepared-dom.js",
  "snapshot-client.d.ts",
  "snapshot-client.js",
];
const FORBIDDEN_FILES: readonly string[] = [
  "core/",
  "runtime/",
  "layout-worker.js",
  "worker-layout.js",
];

function fail(message: string): never {
  throw new Error(`PackageVerificationFailed: ${message}`);
}

export async function verifyPackage(packageRoot: URL = new URL("../", import.meta.url)): Promise<VerifiedArtifact[]> {
  const manifest: PackageManifest = JSON.parse(await readFile(new URL("package.json", packageRoot), "utf8")) as PackageManifest;
  if (manifest.name !== EXPECTED_NAME) fail(`expected ${EXPECTED_NAME}, found ${manifest.name}`);
  try {
    normalizeReleaseVersion(manifest.version);
  } catch {
    fail(`invalid package version ${manifest.version}`);
  }
  if (manifest.license !== "MPL-2.0") fail("manifest must declare MPL-2.0");

  if (!manifest.dependencies?.["@tiqian/core"]) {
    fail("@tiqian/web-component must declare dependency on @tiqian/core");
  }

  for (const forbidden of FORBIDDEN_FILES) {
    if (manifest.files.includes(forbidden)) {
      fail(`${forbidden} must not be included in @tiqian/web-component files`);
    }
  }

  if (manifest.files.includes("styles.css")) {
    fail("styles.css must not be included in @tiqian/web-component files; stylesheet ships from @tiqian/core");
  }
  if (manifest.exports?.["./styles.css"] !== undefined) {
    fail('exports["./styles.css"] must be deleted; the stylesheet resolves from @tiqian/core');
  }
  // The stylesheet is the single source of truth in @tiqian/core; verify it exists.
  {
    const coreStyles: Stats = await stat(new URL("../core/styles.css", packageRoot));
    if (!coreStyles.isFile() || coreStyles.size === 0) fail("@tiqian/core/styles.css is missing or empty");
  }

  for (const required of REQUIRED_FILES) {
    const metadata: Stats = await stat(new URL(required, packageRoot));
    if (!metadata.isFile() || metadata.size === 0) fail(`${required} is missing or empty`);
    if (!manifest.files.includes(required)) fail(`${required} is absent from files`);
  }

  const [license, readme]: readonly [string, string] = await Promise.all([
    readFile(new URL("LICENSE", packageRoot), "utf8"),
    readFile(new URL("README.md", packageRoot), "utf8"),
  ]);
  if (!license.startsWith("Mozilla Public License Version 2.0")) {
    fail("LICENSE is not the MPL-2.0 text");
  }
  if (!readme.includes(EXPECTED_NAME)) fail(`README.md does not name ${EXPECTED_NAME}`);

  const verified: VerifiedArtifact[] = [];
  for (const file of manifest.files) {
    const metadata: Stats = await stat(new URL(file, packageRoot));
    if (metadata.isFile()) {
      verified.push({ path: file, size: metadata.size });
    }
  }
  return verified;
}

const invokedPath: string | null = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : null;
if (invokedPath === import.meta.url) {
  const artifacts: readonly VerifiedArtifact[] = await verifyPackage();
  for (const artifact of artifacts) {
    console.log(`verified ${artifact.path} (${artifact.size} bytes)`);
  }
}
