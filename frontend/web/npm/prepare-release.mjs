#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const packageRoot = fileURLToPath(new URL("./", import.meta.url));
const repositoryRoot = fileURLToPath(new URL("../../..", import.meta.url));
const PACKAGE_NAME = "@tiqian/prose";
const RELEASE_VERSION = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$/u;

export function normalizeReleaseVersion(input) {
  const version = String(input ?? "").trim();
  const match = RELEASE_VERSION.exec(version);
  if (!match) throw new Error(`InvalidReleaseVersion:${version || "missing"}`);
  const prerelease = match[4];
  if (prerelease?.split(".").some((part) => /^0\d+$/u.test(part))) {
    throw new Error(`InvalidReleaseVersion:${version}`);
  }
  return version;
}

export function releaseTag(version) {
  return `${PACKAGE_NAME}@${normalizeReleaseVersion(version)}`;
}

export function releaseCommitSubject(version) {
  const normalized = normalizeReleaseVersion(version);
  const label = normalized.includes("-") ? normalized.slice(normalized.indexOf("-") + 1) : normalized;
  return `chore(web): prepare ${label} release`;
}

function run(command, arguments_, options = {}) {
  const result = spawnSync(command, arguments_, {
    cwd: options.cwd ?? repositoryRoot,
    encoding: "utf8",
    stdio: options.capture ? "pipe" : "inherit",
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    const detail = [result.stdout, result.stderr].filter(Boolean).join("\n").trim();
    throw new Error(`ReleaseCommandFailed:${command} ${arguments_.join(" ")}${detail ? `\n${detail}` : ""}`);
  }
  return String(result.stdout ?? "").trim();
}

function git(arguments_, options = {}) {
  return run("git", arguments_, { ...options, cwd: repositoryRoot });
}

function runNpm(arguments_) {
  const npmCli = process.env.npm_execpath;
  const command = npmCli ? process.execPath : process.platform === "win32" ? "npm.cmd" : "npm";
  const args = npmCli ? [npmCli, ...arguments_] : arguments_;
  return run(command, args, { cwd: packageRoot });
}

function tagExists(tag) {
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

async function prepareRelease(versionInput) {
  const version = normalizeReleaseVersion(versionInput);
  const tag = releaseTag(version);
  const subject = releaseCommitSubject(version);
  const branch = git(["branch", "--show-current"], { capture: true });
  if (branch !== "main") throw new Error(`ReleaseBranchMustBeMain:${branch || "detached"}`);
  const status = git(["status", "--porcelain", "--untracked-files=all"], { capture: true });
  if (status) throw new Error(`ReleaseWorkingTreeMustBeClean:\n${status}`);
  if (tagExists(tag)) throw new Error(`ReleaseTagAlreadyExists:${tag}`);

  const manifest = JSON.parse(await readFile(resolve(packageRoot, "package.json"), "utf8"));
  if (manifest.name !== PACKAGE_NAME) throw new Error(`ReleasePackageMismatch:${manifest.name}`);
  if (manifest.version === version) throw new Error(`ReleaseVersionUnchanged:${version}`);

  runNpm(["version", version, "--no-git-tag-version"]);
  const lock = JSON.parse(await readFile(resolve(packageRoot, "package-lock.json"), "utf8"));
  if (lock.version !== version || lock.packages?.[""]?.version !== version) {
    throw new Error(`ReleaseLockVersionMismatch:${version}`);
  }

  runNpm(["run", "verify:release"]);
  const changedFiles = git(["diff", "--name-only"], { capture: true })
    .split("\n")
    .filter(Boolean)
    .sort();
  const expectedChangedFiles = [
    "frontend/web/npm/package-lock.json",
    "frontend/web/npm/package.json",
  ];
  const untrackedFiles = git(["ls-files", "--others", "--exclude-standard"], { capture: true });
  const stagedFiles = git(["diff", "--cached", "--name-only"], { capture: true });
  if (
    JSON.stringify(changedFiles) !== JSON.stringify(expectedChangedFiles) ||
    untrackedFiles || stagedFiles
  ) {
    throw new Error("ReleaseVerificationChangedUnexpectedFiles");
  }
  git(["add", "frontend/web/npm/package.json", "frontend/web/npm/package-lock.json"]);
  git(["diff", "--cached", "--check"]);
  git(["commit", "-m", subject]);
  const commit = git(["rev-parse", "HEAD"], { capture: true });
  git(["tag", "-a", tag, commit, "-m", tag]);
  const tagCommit = git(["rev-parse", `${tag}^{}`], { capture: true });
  if (tagCommit !== commit) throw new Error(`ReleaseTagTargetMismatch:${tag}`);
  const finalStatus = git(["status", "--porcelain", "--untracked-files=all"], { capture: true });
  if (finalStatus) throw new Error(`ReleaseWorkingTreeChangedAfterTag:\n${finalStatus}`);

  console.log(`prepared ${tag} at ${commit}`);
  console.log(`review the commit, then run: git push origin main '${tag}'`);
}

const invokedPath = process.argv[1] ? pathToFileURL(resolve(process.argv[1])).href : null;
if (invokedPath === import.meta.url) {
  await prepareRelease(process.argv[2]);
}
