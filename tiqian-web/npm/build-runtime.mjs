#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const gradleWrapper = fileURLToPath(new URL("../../gradlew", import.meta.url));
const result = spawnSync(gradleWrapper, [
  ":tiqian-shaping-web:clean",
  ":tiqian-web-precompute:clean",
  ":tiqian-web:clean",
  ":tiqian-web:assembleNpmPackage",
  "--no-build-cache",
], {
  cwd: repositoryRoot,
  stdio: "inherit",
});

if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
