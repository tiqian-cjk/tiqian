#!/usr/bin/env bash
# Stage the local data inputs that Haxe generation reads at compile time.
#
# One input lives outside git:
#   tools/unicode-data/            read by reflaxe.unicode.GraphemeData
#
# It has two in-tree sources, so a fresh clone needs no prepared checkout:
#   .haxelib/boring/git/tools/unicode-data/  the pinned boring checkout
#   $BORING_SOURCE/tools/unicode-data/       the boring flake input source
#
# Usage:
#   bash tools/setup-haxe-env.sh              # stage from the in-repo sources
#   bash tools/setup-haxe-env.sh <checkout>   # stage from a prepared checkout
set -euo pipefail

TARGET="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
SOURCE="${1:-}"

# The pinned boring checkout carries the Unicode 17.0.0 data files.
UNICODE_SOURCE=".haxelib/boring/git/tools/unicode-data"

stage() {
  local rel="$1" src="$2"
  if [ -e "$TARGET/$rel" ] || [ -L "$TARGET/$rel" ]; then
    echo "  = $rel (already present)"
    return 0
  fi
  if [ ! -e "$src" ]; then
    echo "setup-haxe-env: missing source input: $src" >&2
    return 1
  fi
  mkdir -p "$(dirname "$TARGET/$rel")"
  cp -pR "$src" "$TARGET/$rel"
  # The boring flake source in the nix store is read-only; make the staged
  # copy writable so it matches the .haxelib checkout path.
  chmod -R u+w "$TARGET/$rel"
  echo "  + $rel (copied from $src)"
  return 0
}

echo "setup-haxe-env: target $TARGET"

# Candidate sources, tried in order: explicit argument, the in-repo pinned
# boring checkout, then the boring flake input source.
candidates=()
if [ -n "$SOURCE" ]; then
  if [ -d "$SOURCE" ]; then
    candidates+=("$(cd "$SOURCE" && pwd -P)/tools/unicode-data")
  else
    candidates+=("$SOURCE/tools/unicode-data")
  fi
fi
candidates+=("$TARGET/$UNICODE_SOURCE")
if [ -n "${BORING_SOURCE:-}" ]; then
  candidates+=("$BORING_SOURCE/tools/unicode-data")
fi

tried=()
for src in "${candidates[@]}"; do
  tried+=("$src")
  echo "setup-haxe-env: trying source $src"
  if stage tools/unicode-data "$src"; then
    exit 0
  fi
done

echo "setup-haxe-env: no usable source input; tried:" >&2
for p in "${tried[@]}"; do
  echo "  - $p" >&2
done
exit 1
