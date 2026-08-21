// Temporary manifest swap for the snapshot publication lane. GitHub Packages
// requires the npm scope to equal the repository owner, so snapshots publish
// as @tiqian-cjk while registry releases keep @tiqian. `apply` rewrites the
// five manifests in place and keeps a backup; `restore` puts them back.
// Only the manual snapshot workflow runs this; release packaging never does.

import { existsSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = dirname(fileURLToPath(import.meta.url));
const backupPath = join(root, ".snapshot-swap.json");
const platforms = [
  "darwin-arm64",
  "linux-arm64-gnu",
  "linux-x64-gnu",
  "win32-x64-msvc",
];
const manifestPaths = [
  join(root, "package.json"),
  ...platforms.map((platform) => join(root, "platforms", platform, "package.json")),
];

const swapScope = (name, scope) => {
  const slash = name.indexOf("/");
  if (!name.startsWith("@") || slash < 0) {
    throw new Error(`SnapshotSwapNameUnscoped: ${name}`);
  }
  return `${scope}${name.slice(slash)}`;
};

const apply = (version, scope) => {
  if (!scope.startsWith("@") || scope.includes("/")) {
    throw new Error(`SnapshotSwapScopeInvalid: ${scope}`);
  }
  if (version === "" || scope === "") {
    throw new Error("SnapshotSwapArgumentsMissing");
  }
  const backup = {};
  for (const path of manifestPaths) {
    const original = readFileSync(path, "utf8");
    const manifest = JSON.parse(original);
    manifest.name = swapScope(manifest.name, scope);
    manifest.version = version;
    if (manifest.optionalDependencies !== undefined) {
      const swapped = {};
      for (const [name] of Object.entries(manifest.optionalDependencies)) {
        swapped[swapScope(name, scope)] = version;
      }
      manifest.optionalDependencies = swapped;
    }
    backup[path] = original;
    writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`);
  }
  writeFileSync(backupPath, JSON.stringify(backup));
  console.log(`snapshot swap applied: ${scope} at ${version}`);
};

const restore = () => {
  if (!existsSync(backupPath)) {
    throw new Error("SnapshotSwapBackupMissing");
  }
  const backup = JSON.parse(readFileSync(backupPath, "utf8"));
  for (const [path, original] of Object.entries(backup)) {
    writeFileSync(path, original);
  }
  rmSync(backupPath);
  console.log("snapshot swap restored");
};

const [command, ...args] = process.argv.slice(2);
if (command === "apply") {
  if (args.length !== 2) {
    throw new Error("usage: snapshot-swap.mjs apply <version> <scope>");
  }
  apply(args[0], args[1]);
} else if (command === "restore") {
  if (args.length !== 0) {
    throw new Error("usage: snapshot-swap.mjs restore");
  }
  restore();
} else {
  throw new Error("usage: snapshot-swap.mjs <apply|restore> [...]");
}
