#!/usr/bin/env bash
# Prepare a tiqian checkout (or git worktree) for Haxe generation and for the
# boring bundle driver.
#
# Three inputs the Haxe compiler reads during generation are gitignored, so a
# fresh clone or a new worktree has none of them and the first generation fails
# with an error that names neither the driver nor the setup:
#
#   .haxelib                      -lib boring / -lib reflaxe resolve here, and
#                                 the vendored boring checkout inside it is the
#                                 generator revision that decides what the
#                                 generated code contains
#   engine-haxe/baseline-goldens  GoldenDataMacros.init() reads the layout-dump
#                                 and process-trace goldens from it
#   tools/unicode-data            the pinned Unicode tables Graphemes.hx and the
#                                 other data classes read at compile time
#
# Usage, from the checkout to prepare:
#
#   bash tools/setup-haxe-env.sh [<source checkout>]
#
# <source checkout> defaults to the main tiqian checkout next to this worktree.
# Existing paths are left alone; the script only fills what is missing.
set -u

TARGET="$(git rev-parse --show-toplevel)"
SOURCE="${1:-}"

if [ -z "$SOURCE" ]; then
  # The main working tree of this repository is the canonical source. A sibling
  # directory is the wrong guess: the compiler checkout next to this one also
  # satisfies a path-existence test on tools/unicode-data.
  SOURCE="$(git worktree list --porcelain | sed -n 's/^worktree //p' | head -1)"
fi

if [ -z "$SOURCE" ] || [ ! -d "$SOURCE" ]; then
  echo "setup-haxe-env: cannot find a source checkout with .haxelib and tools/unicode-data." >&2
  echo "Pass one explicitly: bash tools/setup-haxe-env.sh /path/to/tiqian" >&2
  exit 2
fi

echo "setup-haxe-env: target $TARGET"
echo "setup-haxe-env: source $SOURCE"

link_or_copy() { # <relative path>
  local rel="$1"
  if [ -e "$TARGET/$rel" ]; then
    echo "  = $rel (already present)"
    return
  fi
  mkdir -p "$(dirname "$TARGET/$rel")"
  # .haxelib is referenced by the generation entries as a relative path, so a
  # symlink keeps one vendored checkout shared instead of copied per worktree.
  if [ "$rel" = ".haxelib" ]; then
    ln -sfn "$SOURCE/$rel" "$TARGET/$rel"
    echo "  + $rel -> $SOURCE/$rel (symlink)"
  else
    cp -a "$SOURCE/$rel" "$TARGET/$rel"
    echo "  + $rel (copied)"
  fi
}

link_or_copy ".haxelib"
link_or_copy "engine-haxe/baseline-goldens"
link_or_copy "tools/unicode-data"

echo "setup-haxe-env: done"
echo "setup-haxe-env: generator revision $TARGET/.haxelib/boring/git = $(git -C "$TARGET/.haxelib/boring/git" rev-parse --short HEAD 2>/dev/null || echo unknown)"
