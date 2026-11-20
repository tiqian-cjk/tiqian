// Temporary manifest and source swap for the snapshot publication lane.
// GitHub Packages requires the npm scope to equal the repository owner and
// links a package to the repository named in its manifest, so a snapshot
// published from a fork must carry the fork's name while registry releases
// keep @tiqian and the canonical repository. `apply` rewrites every snapshot
// manifest (precompute and its platform binaries, the astro and sveltekit
// integrations, core, prose, react, and ffi), the `@tiqian/*` specifiers
// embedded in the shipped sources, and keeps a backup; `restore` puts
// everything back. The swapped sources no longer resolve the local
// `@tiqian/*` dev links, so publish with `--ignore-scripts` after the
// unswapped tree passed its tests. Only the manual snapshot workflow runs
// this; release packaging never does.

import { existsSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const root: string = dirname(fileURLToPath(import.meta.url));
const selfPath: string = fileURLToPath(import.meta.url);
const backupPath: string = join(root, ".snapshot-swap.json");
const platforms: readonly string[] = [
  "darwin-arm64",
  "linux-arm64-gnu",
  "linux-x64-gnu",
  "win32-x64-msvc",
];
const manifestPaths: readonly string[] = [
  join(root, "package.json"),
  ...platforms.map((platform: string): string => join(root, "platforms", platform, "package.json")),
  join(root, "../../client/core/package.json"),
  join(root, "../../client/web-component/package.json"),
  join(root, "../../client/react/package.json"),
  join(root, "../../client/astro/package.json"),
  join(root, "../../client/sveltekit/package.json"),
  join(root, "../../client/engine-runtime/package.json"),
];
// Source roots whose text files may embed the rescope set below. node_modules
// is excluded everywhere so the workspace symlinks into the client packages
// are never followed and rewritten twice.
const sourceRoots: readonly string[] = [
  join(root, "../../client/core"),
  join(root, "../../client/web-component"),
  join(root, "../../client/react"),
  join(root, "../../client/astro"),
  join(root, "../../client/sveltekit"),
  root,
  join(root, "../../client/engine-runtime"),
];
const excludedDirectories: readonly Set<string> = new Set(["node_modules", ".parcel-cache", ".git"]);
const sourceExtensions: readonly string[] = [".js", ".cjs", ".mjs", ".ts", ".mts"];
// The package names that appear as specifiers in shipped sources and as
// dependency keys in the snapshot manifests. Each entry is rescoped to the
// fork scope and pinned to the snapshot version.
const rescopeSet: readonly string[] = [
  "@tiqian/ffi",
  "@tiqian/core",
  "@tiqian/web-component",
  "@tiqian/precompute",
];

interface RepositoryObject {
  type?: string;
  url?: string;
  directory?: string;
}

interface PackageManifest {
  name: string;
  version: string;
  private?: boolean;
  dependencies?: Record<string, string>;
  optionalDependencies?: Record<string, string>;
  peerDependencies?: Record<string, string>;
  repository?: RepositoryObject | string;
}

type ManifestBackup = Record<string, string>;

const swapScope = (name: string, scope: string): string => {
  const slash: number = name.indexOf("/");
  if (!name.startsWith("@") || slash < 0) {
    throw new Error(`SnapshotSwapNameUnscoped: ${name}`);
  }
  return `${scope}${name.slice(slash)}`;
};

// Replaces the github.com owner/repo segment of a repository URL, keeping any
// prefix (git+https://) and the .git suffix; the directory field is untouched.
const swapRepositoryUrl = (url: string, repository: string): string => {
  const marker = "github.com/";
  const start: number = url.indexOf(marker);
  const tail: string = start < 0 ? "" : url.slice(start + marker.length);
  const withoutGit: string = tail.replace(/\.git$/u, "");
  if (start < 0 || !/^[^/]+\/[^/]+$/u.test(withoutGit)) {
    throw new Error(`SnapshotSwapRepositoryUrlUnsupported: ${url}`);
  }
  const suffix: string = tail.endsWith(".git") ? ".git" : "";
  return `${url.slice(0, start + marker.length)}${repository}${suffix}`;
};

// Rewrites one dependency map: entries in the rescope set follow the fork
// scope and the snapshot version; every other entry stays untouched.
const swapDependencyMap = (
  map: Record<string, string>,
  scope: string,
  version: string,
): Record<string, string> => {
  const swapped: Record<string, string> = {};
  for (const [name, value] of Object.entries(map)) {
    if ((rescopeSet as readonly string[]).includes(name)) {
      swapped[swapScope(name, scope)] = version;
    } else {
      swapped[name] = value;
    }
  }
  return swapped;
};

const collectSourceFiles = (directory: string): string[] => {
  const files: string[] = [];
  for (const entry of readdirSync(directory)) {
    const path: string = join(directory, entry);
    const stats = statSync(path);
    if (stats.isDirectory()) {
      if (excludedDirectories.has(entry)) continue;
      files.push(...collectSourceFiles(path));
    } else if (sourceExtensions.some((extension: string): boolean => path.endsWith(extension))) {
      files.push(path);
    }
  }
  return files;
};

const apply = (version: string, scope: string, repository: string): void => {
  if (!scope.startsWith("@") || scope.includes("/")) {
    throw new Error(`SnapshotSwapScopeInvalid: ${scope}`);
  }
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/u.test(repository)) {
    throw new Error(`SnapshotSwapRepositoryInvalid: ${repository}`);
  }
  if (version === "" || scope === "" || repository === "") {
    throw new Error("SnapshotSwapArgumentsMissing");
  }
  const backup: ManifestBackup = {};
  for (const path of manifestPaths) {
    const original: string = readFileSync(path, "utf8");
    const manifest: PackageManifest = JSON.parse(original) as PackageManifest;
    manifest.name = swapScope(manifest.name, scope);
    manifest.version = version;
    // react ships a private marker in the working tree; a publishable
    // snapshot tarball must not carry it.
    delete manifest.private;
    if (manifest.dependencies !== undefined) {
      manifest.dependencies = swapDependencyMap(manifest.dependencies, scope, version);
    }
    if (manifest.optionalDependencies !== undefined) {
      manifest.optionalDependencies = swapDependencyMap(manifest.optionalDependencies, scope, version);
    }
    if (manifest.peerDependencies !== undefined) {
      manifest.peerDependencies = swapDependencyMap(manifest.peerDependencies, scope, version);
    }
    if (manifest.repository !== undefined) {
      const repositoryField: RepositoryObject | string = manifest.repository;
      if (
        typeof repositoryField !== "object" ||
        repositoryField === null ||
        typeof repositoryField.url !== "string"
      ) {
        throw new Error("SnapshotSwapRepositoryFieldInvalid");
      }
      repositoryField.url = swapRepositoryUrl(repositoryField.url, repository);
    }
    backup[path] = original;
    writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`);
  }
  const replacements: [string, string][] = rescopeSet.map(
    (name: string): [string, string] => [name, swapScope(name, scope)],
  );
  for (const sourceRoot of sourceRoots) {
    if (!existsSync(sourceRoot)) continue;
    for (const path of collectSourceFiles(sourceRoot)) {
      // The swap script's own literals name the rescope set; rewriting them
      // would corrupt the set mid-flight and break a second apply.
      if (path === selfPath) continue;
      const original: string = readFileSync(path, "utf8");
      let swapped: string = original;
      for (const [name, rescoped] of replacements) {
        swapped = swapped.split(name).join(rescoped);
      }
      if (swapped !== original) {
        backup[path] = original;
        writeFileSync(path, swapped);
      }
    }
  }
  writeFileSync(backupPath, JSON.stringify(backup));
  const fileCount: number = Object.keys(backup).length - manifestPaths.length;
  console.log(`snapshot swap applied: ${scope} at ${version} for ${repository}`);
  console.log(`manifests rewritten: ${manifestPaths.length}; sources rewritten: ${fileCount}`);
};

const restore = (): void => {
  if (!existsSync(backupPath)) {
    throw new Error("SnapshotSwapBackupMissing");
  }
  const backup: ManifestBackup = JSON.parse(readFileSync(backupPath, "utf8")) as ManifestBackup;
  for (const [path, original] of Object.entries(backup)) {
    writeFileSync(path, original);
  }
  rmSync(backupPath);
  console.log("snapshot swap restored");
};

const [command, ...args]: string[] = process.argv.slice(2);
if (command === "apply") {
  if (args.length !== 3) {
    throw new Error("usage: snapshot-swap.ts apply <version> <scope> <owner/repo>");
  }
  apply(args[0], args[1], args[2]);
} else if (command === "restore") {
  if (args.length !== 0) {
    throw new Error("usage: snapshot-swap.ts restore");
  }
  restore();
} else {
  throw new Error("usage: snapshot-swap.ts <apply|restore> [...]");
}
