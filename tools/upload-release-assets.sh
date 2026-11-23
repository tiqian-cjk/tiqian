#!/usr/bin/env bash
# Upload files to the GitHub release of a tag under their own names.
#
# The registry metadata names these files as release assets. A re-run of the
# registry job finds the assets already uploaded: an asset with the same bytes
# stays in place, and different bytes stop the script, because the published
# metadata would no longer describe the asset.
#
# Usage: tools/upload-release-assets.sh <tag> <file>...
# Needs GH_TOKEN and GITHUB_REPOSITORY, as a workflow step provides them.
set -euo pipefail

tag="${1:?pass the release tag}"
shift
repository="${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY to owner/repo}"
temp="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"

# The assets endpoint pages; a release carries more assets than one page.
release_id="$(gh api "repos/${repository}/releases/tags/${tag}" --jq '.id')"
present="$(gh api --paginate "repos/${repository}/releases/${release_id}/assets?per_page=100" --jq '.[].name')"
for file in "$@"; do
  name="$(basename "$file")"
  if grep -qxF "$name" <<<"$present"; then
    existing="${temp}/existing-${name}"
    gh release download "$tag" --repo "$repository" --pattern "$name" --output "$existing" --clobber
    if ! cmp -s "$file" "$existing"; then
      echo "::error::$name is already a release asset with different bytes"
      exit 1
    fi
    echo "$name is already uploaded"
  else
    gh release upload "$tag" "$file" --repo "$repository"
  fi
done
