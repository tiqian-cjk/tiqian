#!/usr/bin/env bash
# Publish one built npm tarball, or confirm it already landed.
#
# A release re-runs after a partial failure, and npm refuses to overwrite a
# version that already landed. This script makes the publish step idempotent:
# when the registry already holds the version, the local tarball's sha1 must
# equal the published shasum and the step succeeds without contacting the
# registry for a write; when it differs, the step fails because the release
# would ship an artifact nobody verified.
#
# Authentication is the caller's: the release lanes grant id-token: write and
# this script never reads a token, so trusted publishing authenticates the
# upload. A run without that permission fails at npm rather than silently
# publishing with a long-lived credential.
#
# Usage: tools/npm-publish.sh <tarball> [--tag alpha]
set -uo pipefail

tarball=""
tag="alpha"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --tag) tag="${2:-}"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) tarball="$1"; shift ;;
  esac
done
if [ -z "$tarball" ] || [ ! -f "$tarball" ]; then
  echo "usage: tools/npm-publish.sh <tarball> [--tag alpha]" >&2
  exit 2
fi

manifest="$(tar -xzOf "$tarball" package/package.json)"
name="$(printf '%s' "$manifest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["name"])')"
version="$(printf '%s' "$manifest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')"
local_sha1="$(sha1sum "$tarball" | cut -d' ' -f1)"
echo "tarball: $(basename "$tarball") -> $name@$version (sha1 $local_sha1)"

published_sha1="$(npm view "$name@$version" dist.shasum 2>/dev/null | tr -d '[:space:]')"
if [ -n "$published_sha1" ]; then
  if [ "$published_sha1" = "$local_sha1" ]; then
    echo "$name@$version is already published with the same shasum; nothing to upload"
    exit 0
  fi
  echo "::error::$name@$version is already published with shasum $published_sha1, the local tarball is $local_sha1"
  exit 1
fi

npm publish "$tarball" --ignore-scripts --access public --tag "$tag"
