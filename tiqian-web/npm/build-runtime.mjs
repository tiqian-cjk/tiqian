#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const repositoryRoot = fileURLToPath(new URL("../..", import.meta.url));
const isWindows = process.platform === "win32";
const gradleWrapper = fileURLToPath(new URL(
  isWindows ? "../../gradlew.bat" : "../../gradlew",
  import.meta.url,
));
const gradleArguments = [
  ":tiqian-shaping-web:clean",
  ":tiqian-web-precompute:clean",
  ":tiqian-web:clean",
  ":tiqian-web:assembleNpmPackage",
  "--no-build-cache",
];
// WindowsBatchWrapperViaComSpec: .bat files are cmd scripts rather than native
// executables. Invoke the wrapper through ComSpec while keeping Unix on the
// directly executable Gradle wrapper.
const command = isWindows
  ? process.env.ComSpec ?? process.env.COMSPEC ?? "cmd.exe"
  : gradleWrapper;
const commandArguments = isWindows
  ? ["/d", "/c", "call", gradleWrapper, ...gradleArguments]
  : gradleArguments;
const result = spawnSync(command, commandArguments, {
  cwd: repositoryRoot,
  stdio: "inherit",
});

if (result.error) throw result.error;
process.exitCode = result.status ?? 1;
