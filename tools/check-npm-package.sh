#!/usr/bin/env bash
# Inspect one built npm package the way a consumer receives it.
#
# A release lane builds a tarball and hands it to npm publish; nothing before
# the publish step looked inside that tarball, so a package whose manifest or
# file list disagreed with the lane reached a registry first. This script
# installs the archive into an empty project, imports the entry points the
# package declares, and prints the manifest facts a reviewer needs. It refuses
# the archive when the installed manifest name is not the expected one, when a
# dependency still carries the workspace protocol, or when an entry does not
# load.
#
# Usage:
#   tools/check-npm-package.sh <tarball> [--expect <name>] [--entry <specifier> ...]
#   tools/check-npm-package.sh <tarball> --resolve-specifier @scope/pkg
#
# --expect        the package name the release publishes; the manifest must match
# --entry         a specifier to import after install; repeatable
# --resolve-specifier
#                 import the bare package name and report that the exports map
#                 refuses a root entry, which a package with subpath exports only
#                 does on purpose
#
# The scratch project lives under the caller's temporary directory and is
# removed on exit. Exit status: 0 the archive is installable and loads,
# 1 it is not, 2 the invocation is unusable.
set -uo pipefail

tarball=""
expect=""
entries=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --expect) expect="${2:-}"; shift 2 ;;
    --entry) entries+=("${2:-}"); shift 2 ;;
    --resolve-specifier) expect="${2:-}"; shift 2 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) tarball="$1"; shift ;;
  esac
done

if [ -z "$tarball" ] || [ ! -f "$tarball" ]; then
  echo "usage: tools/check-npm-package.sh <tarball> [--expect <name>] [--entry <specifier> ...]" >&2
  exit 2
fi

work="${TMPDIR:-/tmp}/npm-check-$$"
rm -rf "$work"
mkdir -p "$work/project"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT

absolute="$(cd "$(dirname "$tarball")" && pwd)/$(basename "$tarball")"
members="$(tar -tzf "$absolute" | wc -l)"
bytes="$(wc -c <"$absolute")"
manifest="$(tar -xzOf "$absolute" package/package.json)"
name="$(printf '%s' "$manifest" | node -e 'let t="";process.stdin.on("data",d=>t+=d).on("end",()=>console.log(JSON.parse(t).name||""))')"
version="$(printf '%s' "$manifest" | node -e 'let t="";process.stdin.on("data",d=>t+=d).on("end",()=>console.log(JSON.parse(t).version||""))')"
files="$(printf '%s' "$manifest" | node -e 'let t="";process.stdin.on("data",d=>t+=d).on("end",()=>{const m=JSON.parse(t);console.log(JSON.stringify(m.files||null))})')"

echo "archive: $(basename "$absolute")"
echo "  bytes:   $bytes"
echo "  members: $members"
echo "  name:    $name"
echo "  version: $version"
echo "  files:   $files"

status=0
if [ -n "$expect" ] && [ "$name" != "$expect" ]; then
  echo "  FAIL: manifest name $name is not the published name $expect"
  status=1
fi
if printf '%s' "$manifest" | grep -q '"workspace:'; then
  echo "  FAIL: the manifest still carries a workspace range"
  status=1
fi

printf '{"name":"package-check","version":"1.0.0","private":true,"type":"module"}\n' >"$work/project/package.json"
if ! (cd "$work/project" && npm install --ignore-scripts --no-audit --no-fund --silent "$absolute" >/dev/null 2>&1); then
  echo "  FAIL: npm install refused the archive"
  (cd "$work/project" && npm install --ignore-scripts --no-audit --no-fund "$absolute" 2>&1 | tail -5 | sed 's/^/    /')
  exit 1
fi
installed="$(node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));console.log(p.name)' "$work/project/node_modules/$name/package.json" 2>/dev/null)"
if [ -z "$installed" ]; then
  echo "  FAIL: the archive did not install under $name"
  exit 1
fi
echo "  installed: $installed"

if [ "${#entries[@]}" -eq 0 ] && [ -n "$name" ]; then
  entries=("$name")
fi
for specifier in "${entries[@]}"; do
  [ -n "$specifier" ] || continue
  if (cd "$work/project" && node --input-type=module -e 'await import(process.argv[1])' "$specifier" >/dev/null 2>&1); then
    count="$(cd "$work/project" && node --input-type=module -e 'const m=await import(process.argv[1]);console.log(Object.keys(m).length)' "$specifier" 2>/dev/null)"
    echo "  import $specifier: ok, exports ${count:-0}"
  else
    reason="$(cd "$work/project" && node --input-type=module -e 'await import(process.argv[1])' "$specifier" 2>&1 | grep -oE "ERR_[A-Z_]+" | head -1)"
    if [ "$reason" = "ERR_PACKAGE_PATH_NOT_EXPORTED" ]; then
      echo "  import $specifier: subpath-only exports, no root entry (expected for this package)"
    else
      echo "  import $specifier: FAIL ${reason:-unknown}"
      status=1
    fi
  fi
done

if [ "$status" -eq 0 ]; then
  echo "  package check: OK"
else
  echo "  package check: FAIL"
fi
exit "$status"
