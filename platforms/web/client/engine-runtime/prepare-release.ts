#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const packageRoot: string = fileURLToPath(new URL("./", import.meta.url));
const repositoryRoot: string = fileURLToPath(new URL("../../..", import.meta.url));
const PACKAGE_NAME: string = "@tiqian/ffi";
const RELEASE_VERSION: RegExp = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/u;

export function normalizeReleaseVersion(input: string | null | undefined): string {
  const version: string = String(input ?? "").trim();
  const match: RegExpExecArray | null = RELEASE_VERSION.exec(version);
  if (!match) throw new Error(`InvalidReleaseVersion:${version || "missing"}`);
  const prerelease: string | undefined = match[4];
  if (prerelease?.split(".").some((part: string): boolean => /^0\d+$/u.test(part))) {
    throw new Error(`InvalidReleaseVersion:${version}`);
  }
  return version;
}

export function releaseTag(version: string): string {
  return `${PACKAGE_NAME}@${normalizeReleaseVersion(version)}`;
}

export function releaseCommitSubject(version: string): string {
  const normalized: string = normalizeReleaseVersion(version);
  const label: string = normalized.includes("-") ? normalized.slice(normalized.indexOf("-") + 1) : normalized;
  return `chore(ffi): prepare ${label} release`;
}

interface RunOptions {
  readonly cwd?: string;
  readonly capture?: boolean;
}

function run(command: string, arguments_: readonly string[], options: RunOptions = {}): string {
  const result = spawnSync(command, arguments_, {
    cwd: options.cwd ?? repositoryRoot,
    encoding: "utf8",
    stdio: options.capture ? "pipe" : "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const detail: string = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
    throw new Error(`ReleaseCommandFailed:${command} ${arguments_.join(" ")}${detail ? `\n${detail}` : ""}`);
  }
  return String(result.stdout ?? "").trim();
}

function git(arguments_: readonly string[], options: RunOptions = {}): string {
  return run("git", arguments_, { ...options, cwd: repositoryRoot });
}

function runNpm(arguments_: readonly string[]): string {
  const npmCli: string | undefined = process.env.npm_execpath;
  const command: string = npmCli ? process.execPath : process.platform === "win32" ? "npm.cmd" : "npm";
  const args: readonly string[] = npmCli ? [npmCli, ...arguments_] : arguments_;
  return run(command, args, { cwd: packageRoot });
}

function tagExists(tag: string): boolean {
  const result = spawnSync("git", ["show-ref", "--verify", "--quiet", `refs/tags/${tag}`], {
    cwd: repositoryRoot,
    stdio: "ignore",
  });
  if (result.error) throw result.error;
  if (result.status !== 0 && result.status !== 1) {
    throw new Error(`ReleaseTagProbeFailed:${tag}`);
  }
  return result.status === 0;
}

interface PackageManifest {
  readonly name: string;
  readonly version: string;
}

interface PackageLockPackage {
  readonly version?: string;
}

interface PackageLock {
  readonly version: string;
  readonly packages?: Readonly<Record<string, PackageLockPackage>>;
}

async function prepareRelease(versionInput: string | null | undefined): Promise<void> {
  const version: string = normalizeReleaseVersion(versionInput);
  const tag: string = releaseTag(version);
  const subject: string = releaseCommitSubject(version);
  const branch: string = git(["branch", "--show-current"], { capture: true });
  if (branch !== "main") throw new Error(`ReleaseBranchMustBeMain:${branch || "detached"}`);
  const status: string = git(["status", "--porcelain", "--untracked-files=all"], { capture: true });
  if (status) throw new Error(`ReleaseWorkingTreeMustBeClean:\n${status}`);
  if (tagExists(tag)) throw new Error(`ReleaseTagAlreadyExists:${tag}`);

  const manifest: PackageManifest = JSON.parse(await readFile(resolve(packageRoot, "package.json"), "utf8")) as PackageManifest;
  if (manifest.name !== PACKAGE_NAME) throw new Error(`ReleasePackageMismatch:${manifest.name}`);
  if (manifest.version === version) throw new Error(`ReleaseVersionUnchanged:${version}`);

  runNpm(["version", version, "--no-git-tag-version"]);
  const lock: PackageLock = JSON.parse(await readFile(resolve(packageRoot, "package-lock.json"), "utf8")) as PackageLock;
  if (lock.version !== version || lock.packages?.[""]?.version !== version) {
    throw new Error(`ReleaseLockVersionMismatch:${version}`);
  }

  runNpm(["run", "verify:release"]);
  const changedFiles: readonly string[] = git(["diff", "--name-only"], { capture: true })
    .split("\n")
    .filter(Boolean)
    .sort();
  const expectedChangedFiles: readonly string[] = [
    "platforms/web/client/engine-runtime/package-lock.json",
    "platforms/web/client/engine-runtime/package.json",
  ];
  const untrackedFiles: string = git(["ls-files", "--others", "--exclude-standard"], { capture: true });
  const stagedFiles: string = git(["diff", "--cached", "--name-only"], { capture: true });
  if (
    JSON.stringify(changedFiles) !== JSON.stringify(expectedChangedFiles) ||
    untrackedFiles || stagedFiles
  ) {
    throw new Error("ReleaseVerificationChangedUnexpectedFiles");
  }
  git(["add", "platforms/web/client/engine-runtime/package.json", "platforms/web/client/engine-runtime/package-lock.json"]);
  git(["diff", "--cached", "--check"]);
  git(["commit", "-m", subject]);
  const commit: string = git(["rev-parse", "HEAD"], { capture: true });
  git(["tag", "-a", tag, commit, "-m", tag]);
  const tagCommit: string = git(["rev-parse", `${tag}^{}`], { capture: true });
  if (tagCommit !== commit) throw new Error(`ReleaseTagTargetMismatch:${tag}`);
  const finalStatus: string = git(["status", "--porcelain", "--untracked-files=all"], { capture: true });
  if (finalStatus) throw new Error(`ReleaseWorkingTreeChangedAfterTag:\n${finalStatus}`);

  console.log(`prepared ${tag} at ${commit}`);
  console.log(`review the commit, then run: git push origin main '${tag}'`);
}

const invokedPath: string | null = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : null;
if (invokedPath === import.meta.url) {
  await prepareRelease(process.argv[2]);
}
