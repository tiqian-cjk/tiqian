#!/usr/bin/env bash
# Point a dist-tag at one published version, with trusted publishing.
#
# The release lanes used to authenticate this step with a long-lived
# NPM_DIST_TAG_TOKEN. That token expires and blocks the whole lane, so the
# step now authenticates through the workflow's OIDC identity, which requires
# npm CLI 11.21.0 or later and the trusted publisher's "Allow npm dist-tag"
# switch. The step reads the current tags first: when they already point at
# the version, no write and no authentication happen, so a re-run of a
# release that published but failed later still succeeds.
#
# Usage: tools/npm-dist-tag.sh --package <name> --version <version> [--tag latest]
set -uo pipefail

package=""
version=""
tag="latest"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --package) package="${2:-}"; shift 2 ;;
    --version) version="${2:-}"; shift 2 ;;
    --tag) tag="${2:-}"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) echo "unexpected argument: $1" >&2; exit 2 ;;
  esac
done
if [ -z "$package" ] || [ -z "$version" ]; then
  echo "usage: tools/npm-dist-tag.sh --package <name> --version <version> [--tag latest]" >&2
  exit 2
fi

current="$(npm view "$package" dist-tags --json 2>/dev/null || echo '{}')"
converged() {
  PACKAGE="$package" VERSION="$version" TAG="$tag" TAGS="$1" node --input-type=module -e '
    const tags = JSON.parse(process.env.TAGS || "{}");
    const want = process.env.VERSION;
    const tag = process.env.TAG;
    const alpha = tag === "alpha" ? want : tags.alpha;
    process.exit(tags[tag] === want && (tag !== "latest" || tags.alpha === want || tags.alpha === undefined) ? 0 : 1);
  '
}

if converged "$current"; then
  echo "$package dist-tags already point $tag at $version: $current"
  exit 0
fi

echo "current dist-tags: $current"
if ! npm dist-tag add "$package@$version" "$tag"; then
  echo "::error::npm dist-tag add $package@$version $tag failed"
  exit 1
fi

# npm accepts a publish or a dist-tag write and applies it later; reads see
# the change only after that. From alpha.9 to alpha.13 this took 75 to 309
# seconds (median 126), and the five-minute window used before missed
# @tiqian/engine 0.1.0-alpha.13 by eight seconds. The poll waits ten minutes.
attempts=60
for attempt in $(seq 1 "$attempts"); do
  current="$(npm view "$package" dist-tags --json 2>/dev/null || echo '{}')"
  if converged "$current"; then
    echo "$package dist-tags converged: $current"
    exit 0
  fi
  [ "$attempt" -lt "$attempts" ] && sleep 10
done
echo "::error::$package dist-tags did not converge on $version (last: $current)"
exit 1
