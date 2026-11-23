const { gt, valid } = require("semver");

async function main() {
  const [packageName, version] = process.argv.slice(2);
  if (!packageName || !valid(version)) {
    throw new Error("Usage: node tools/check-npm-release-order.cjs <package> <version>");
  }

  const url = `https://registry.npmjs.org/${encodeURIComponent(packageName)}`;
  const response = await fetch(url, {
    cache: "no-cache",
    headers: { Accept: "application/vnd.npm.install-v1+json" },
    signal: AbortSignal.timeout(30_000),
  });

  // An unpublished package has no tags to protect.
  if (response.status === 404) return;
  if (!response.ok) {
    throw new Error(`Cannot read npm tags for ${packageName}: HTTP ${response.status}`);
  }

  const { "dist-tags": tags } = await response.json();
  if (!tags || typeof tags !== "object" || Array.isArray(tags)) {
    throw new Error(`Missing or invalid npm tags for ${packageName}`);
  }

  for (const tag of ["alpha", "latest"]) {
    if (!Object.hasOwn(tags, tag)) continue;
    const current = tags[tag];
    if (!valid(current)) {
      throw new Error(`${packageName} has an invalid version for ${tag}: ${current}`);
    }
    if (gt(current, version)) {
      throw new Error(`Refusing to publish ${packageName}@${version}: ${tag} already points to ${current}`);
    }
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
