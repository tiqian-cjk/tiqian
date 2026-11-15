#!/usr/bin/env bash
# Run the release pipeline against a staging version and publish nothing.
#
# The release entrypoints (.github/workflows/release.yml,
# .github/workflows/release-registry.yml and .github/workflows/publish.yml) run
# only on a v*.*.* tag or a published release, so the pack, registry, cargo and
# Maven steps they drive stay unverified until the first real release. This
# script runs the same steps with a staging version and writes every output
# below one staging root. It never tags, never pushes and never contacts an
# official registry.
#
# Usage: scripts/staging-pipeline.sh [--bundles "id ..."] [--stages "name ..."] [--root <dir>]
#
# Stages (default: all of them): align, pack, collect-artifacts, registry-tree,
# staging-isolation, maven-artifact-ids, cargo-consume, maven-local-publish,
# maven-local-repo, summary.
#
# Environment:
#   STAGING_VERSION              version to pack with; defaults to 0.0.0-staging.<short sha>
#   STAGING_ROOT                 output root; defaults to ${RUNNER_TEMP:-$PWD/.task-tmp}/tiqian-staging-<short>
#   STAGING_BUNDLES              bundle ids to pack; defaults to release-matrix.py --list-bundles
#   STAGING_OWNER                owner directory in the staging registry tree; defaults to staging-local
#   EXPECTED_MAVEN_ARTIFACT_IDS  KMP artifactId count to require per maven package; defaults to 9
#
# Every output stays below STAGING_ROOT. The cargo consumer build consumes the
# packed .crate directly, and the Maven publish passes
# -Dmaven.repo.local=<STAGING_ROOT>/maven-repo, so neither the shared ~/.m2 nor
# any package manager cache receives a staging coordinate.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 2

DEFAULT_STAGES="align pack collect-artifacts registry-tree staging-isolation maven-artifact-ids cargo-consume maven-local-publish maven-local-repo summary"
BUNDLES_OVERRIDE=""
STAGES="$DEFAULT_STAGES"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --bundles) BUNDLES_OVERRIDE="${2:-}"; shift 2 ;;
    --stages) STAGES="${2:-}"; shift 2 ;;
    --root) STAGING_ROOT="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "${STAGING_VERSION:-}" ]; then
  STAGING_VERSION="0.0.0-staging.$(git rev-parse --short=7 HEAD)"
fi
SHORT="${STAGING_VERSION##*.}"
ROOT="${STAGING_ROOT:-${RUNNER_TEMP:-$REPO_ROOT/.task-tmp}/tiqian-staging-$SHORT}"
LOGS="$ROOT/logs"
TREE="$ROOT/registry-tree"
ARTIFACTS="$ROOT/release-artifacts"
MAVEN_REPO="$ROOT/maven-repo"
CARGO_ROOT="$ROOT/cargo"
OWNER="${STAGING_OWNER:-staging-local}"
EXPECTED_MAVEN_ARTIFACT_IDS="${EXPECTED_MAVEN_ARTIFACT_IDS:-9}"
ASSET_BASE="https://staging.invalid/tiqian/releases/download/v$STAGING_VERSION"

mkdir -p "$ROOT" "$LOGS" "$ARTIFACTS" "$MAVEN_REPO" "$CARGO_ROOT"

# Run one command inside the flake devShell when the caller is not already in
# it, so the script behaves the same from a CI step and from a bare shell.
in_devshell() {
  if [ -n "${IN_NIX_SHELL:-}" ]; then
    bash -c "$1"
  else
    nix develop -c bash -c "$1"
  fi
}

STEP_NAMES=()
STEP_RCS=()
STEP_SECONDS=()
FAILED=0

run_step() {
  local name="$1"
  shift
  local log="$LOGS/$name.log"
  local t0 t1 rc
  t0="$(date +%s)"
  echo "===== BEGIN $name ====="
  ( "$@" ) >"$log" 2>&1
  rc=$?
  t1="$(date +%s)"
  STEP_NAMES+=("$name")
  STEP_RCS+=("$rc")
  STEP_SECONDS+=("$((t1 - t0))")
  if [ "$rc" -ne 0 ]; then
    FAILED=1
    echo "===== END $name rc=$rc elapsed=$((t1 - t0))s ====="
    tail -20 "$log" | sed 's/^/  /'
    return 0
  fi
  echo "===== END $name rc=0 elapsed=$((t1 - t0))s ====="
}

# Align every package version in boring.json. The registry derives artifact
# names from <package>-<version>, so a packed manifest that still carries the
# placeholder version names a download that cannot exist.
step_align() {
  python3 tools/align-package-versions.py "$STAGING_VERSION"
  if grep -q '"version": "0.1.0"' boring.json; then
    echo "boring.json still carries the placeholder version 0.1.0"
    return 1
  fi
  echo "every package version in boring.json is $STAGING_VERSION"
}

# Pack every bundle of the release matrix, one invocation per bundle, so one
# red bundle does not hide the rest. RegistryMetadata.emitAll writes only the
# bundles of the current invocation, so the tree accumulates across the loop.
step_pack() {
  local ids
  if [ -n "$BUNDLES_OVERRIDE" ]; then
    ids="$BUNDLES_OVERRIDE"
  elif [ -n "${STAGING_BUNDLES:-}" ]; then
    ids="$STAGING_BUNDLES"
  else
    ids="$(python3 tools/release-matrix.py --list-bundles | paste -sd' ' -)"
  fi
  echo "packs: $ids"
  local rc=0
  local id
  local out_root
  out_root="$(python3 -c 'import json, pathlib; text = pathlib.Path("boring.json").read_text(); print(json.loads(text[text.index("{") :])["outRoot"])')"
  for id in $ids; do
    echo "--- pack $id ---"
    # A repeated run with a new staging version would otherwise leave the
    # previous version's artifacts beside the output tree, and both the pack
    # finders and the artifact collection match by name stem. CI checks out
    # fresh; a local checkout does not.
    rm -rf "$out_root/$id"
    if ! boring pack "$id" --registry-out "$TREE" --owner "$OWNER" --repo tiqian --asset-base "$ASSET_BASE"; then
      echo "--- pack $id FAILED ---"
      rc=1
    fi
  done
  return "$rc"
}

# Collect the install units the way release.yml does, so a metadata entry that
# names a file this list never collects fails in the next step.
step_collect() {
  rm -f "$ARTIFACTS"/*
  find engine-haxe/out -path "$ROOT" -prune -o -type f \( \
    -name "*.tgz" -o -name "*.tar.gz" -o -name "*.jar" -o -name "*.crate" \
    -o -name "*.zip" -o -name "*.pom" \) -print0 |
    while IFS= read -r -d "" file; do
      case "$(basename "$file")" in
        *-"$STAGING_VERSION"*) cp -f "$file" "$ARTIFACTS/" ;;
      esac
    done
  if [ -z "$(ls -A "$ARTIFACTS")" ]; then
    echo "no pack artifacts were produced"
    return 1
  fi
  ( cd "$ARTIFACTS" && sha256sum -- * | sort > SHA256SUMS )
  ls -la "$ARTIFACTS"
}

# The same check the release-registry job runs before it commits metadata.
step_check_tree() {
  python3 tools/check-registry-tree.py --tree "$TREE" --artifacts "$ARTIFACTS"
}

# The staging version must not reach a published namespace. The registry tree
# lives below the staging root under a staging owner, every metadata entry
# records the staging version, and every asset URL points at the reserved
# staging.invalid host.
step_isolation() {
  python3 - "$TREE" "$OWNER" "$STAGING_VERSION" "$HOME" <<"PY"
import json
import pathlib
import sys

tree, owner, version, home = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
root = pathlib.Path(tree)
if not root.is_dir():
    sys.exit("the staging registry tree is missing: %s" % tree)
owners = sorted(entry.name for entry in root.iterdir() if entry.is_dir())
if owners != [owner]:
    sys.exit("the tree holds owner directories %s; the staging owner is %s" % (owners, owner))
entries = sorted(root.rglob("metadata.json"))
if not entries:
    sys.exit("the tree holds no metadata.json")
problems = []
for path in entries:
    metadata = json.loads(path.read_text(encoding="utf-8"))
    if metadata.get("version") != version:
        problems.append("%s records version %r, not %r" % (path, metadata.get("version"), version))
    urls = [metadata.get("url", "")]
    urls.extend(item.get("url", "") for item in metadata.get("artifacts", []))
    for url in urls:
        if url and "staging.invalid" not in url:
            problems.append("%s names a non-staging asset url %s" % (path, url))
m2 = pathlib.Path(home, ".m2", "repository", "org", "tiqian")
if m2.exists():
    problems.append("the staging run wrote into the shared Maven repository %s" % m2)
if problems:
    for problem in problems:
        print("FAIL: %s" % problem)
    sys.exit(1)
print("staging isolation ok: owner=%s version=%s entries=%d" % (owner, version, len(entries)))
PY
}

# The registry maven model carries one artifactId per KMP coordinate: the root
# plus eight target modules. A metadata entry without artifactId, or fewer
# distinct values, is the single-artifact shape the release cannot serve.
step_maven_artifact_ids() {
  python3 - "$TREE" "$EXPECTED_MAVEN_ARTIFACT_IDS" <<"PY"
import json
import pathlib
import sys

tree, expected = pathlib.Path(sys.argv[1]), int(sys.argv[2])
found = {}
for path in sorted(tree.rglob("maven/metadata.json")):
    metadata = json.loads(path.read_text(encoding="utf-8"))
    stem = metadata.get("name") or path.parents[2].name
    for item in metadata.get("artifacts", []):
        artifact_id = item.get("artifactId")
        if not artifact_id:
            sys.exit("%s: an artifacts entry carries no artifactId: %s" % (path, item))
        found.setdefault(stem, set()).add(artifact_id)
if not found:
    sys.exit("the tree holds no maven metadata.json")
for stem in sorted(found):
    ids = sorted(found[stem])
    print("maven %s: %d artifactId (%s)" % (stem, len(ids), ", ".join(ids)))
widest = max((len(ids), stem) for stem, ids in found.items())
if widest[0] < expected:
    sys.exit("the widest maven package %s lists %d artifactId values; the KMP model writes the root coordinate plus eight target coordinates (%d)"
             % (widest[1], widest[0], expected))
PY
}

# Consume the packed .crate the way a downstream project does: unpack the exact
# published archive, require the <name>-<version>/ top-level directory cargo
# requires, and build a consumer against it at the default precision and with
# the f32 feature.
step_cargo() {
  local crate top rc=0
  crate="$(ls "$ARTIFACTS"/tiqian-engine-*.crate 2>/dev/null | head -1)"
  if [ -z "$crate" ]; then
    echo "no tiqian-engine .crate was packed"
    return 1
  fi
  rm -rf "$CARGO_ROOT/unpacked" "$CARGO_ROOT/consumer"
  mkdir -p "$CARGO_ROOT/unpacked"
  tar -xzf "$crate" -C "$CARGO_ROOT/unpacked"
  top="$(ls "$CARGO_ROOT/unpacked")"
  echo "crate $(basename "$crate") unpacks to $top"
  if [ "$top" != "tiqian-engine-$STAGING_VERSION" ]; then
    echo "the crate top-level directory is $top; cargo requires tiqian-engine-$STAGING_VERSION"
    return 1
  fi
  mkdir -p "$CARGO_ROOT/consumer/src"
  cat >"$CARGO_ROOT/consumer/Cargo.toml" <<EOF
[package]
name = "tiqian-staging-consumer"
version = "0.0.0"
edition = "2021"

[workspace]

[dependencies]
tiqian-engine = { path = "../unpacked/$top" }
EOF
  printf "fn main() {}\n" >"$CARGO_ROOT/consumer/src/main.rs"
  echo "--- cargo build (default precision) ---"
  ( cd "$CARGO_ROOT/consumer" && CARGO_TARGET_DIR="$CARGO_ROOT/target-default" cargo build ) || rc=1
  echo "--- cargo build --features tiqian-engine/f32 ---"
  ( cd "$CARGO_ROOT/consumer" && CARGO_TARGET_DIR="$CARGO_ROOT/target-f32" cargo build --features "tiqian-engine/f32" ) || rc=1
  return "$rc"
}

# The Maven lane of publish.yml generates the Kotlin tree first and then
# publishes to an isolated repository, so a clean checkout compiles real
# sources rather than an empty source set.
step_maven_publish() {
  in_devshell "bash tools/setup-haxe-env.sh && boring gen kotlin-f32 --project boring.json" || return 1
  TIQIAN_VERSION="$STAGING_VERSION" ./gradlew publishTiqianToMavenLocal \
    -Dmaven.repo.local="$MAVEN_REPO" --no-daemon
}

# The engine module publishes the root coordinate plus eight target modules.
step_maven_local_repo() {
  python3 - "$MAVEN_REPO" "$STAGING_VERSION" <<"PY"
import pathlib
import sys

repo, version = pathlib.Path(sys.argv[1]), sys.argv[2]
expected = [
    "tiqian-engine",
    "tiqian-engine-jvm",
    "tiqian-engine-android",
    "tiqian-engine-iosarm64",
    "tiqian-engine-iossimulatorarm64",
    "tiqian-engine-macosarm64",
    "tiqian-engine-linuxx64",
    "tiqian-engine-linuxarm64",
    "tiqian-engine-mingwx64",
]
missing = []
for artifact in expected:
    pom = repo / "org" / "tiqian" / artifact / version / ("%s-%s.pom" % (artifact, version))
    print("%s %s" % ("ok  " if pom.is_file() else "MISS", pom))
    if not pom.is_file():
        missing.append(artifact)
if missing:
    sys.exit("the isolated Maven repository holds %d of the %d engine coordinates; missing %s"
             % (len(expected) - len(missing), len(expected), ", ".join(missing)))
PY
}

step_summary() {
  local report="$ROOT/report.md"
  {
    echo "# Staging pipeline report"
    echo
    echo "- version: $STAGING_VERSION"
    echo "- staging root: $ROOT"
    echo "- registry owner: $OWNER"
    echo "- asset base: $ASSET_BASE"
    echo
    echo "| step | rc | seconds |"
    echo "| --- | --- | --- |"
    local index
    for index in "${!STEP_NAMES[@]}"; do
      echo "| ${STEP_NAMES[$index]} | ${STEP_RCS[$index]} | ${STEP_SECONDS[$index]} |"
    done
  } >"$report"
  cat "$report"
}

run_named_step() {
  case "$1" in
    align) run_step align step_align ;;
    pack) run_step pack step_pack ;;
    collect-artifacts) run_step collect-artifacts step_collect ;;
    registry-tree) run_step registry-tree step_check_tree ;;
    staging-isolation) run_step staging-isolation step_isolation ;;
    maven-artifact-ids) run_step maven-artifact-ids step_maven_artifact_ids ;;
    cargo-consume) run_step cargo-consume step_cargo ;;
    maven-local-publish) run_step maven-local-publish step_maven_publish ;;
    maven-local-repo) run_step maven-local-repo step_maven_local_repo ;;
    summary) run_step summary step_summary ;;
    *) echo "unknown stage: $1" >&2; exit 2 ;;
  esac
}

for stage in $STAGES; do
  run_named_step "$stage"
done

echo
if [ "$FAILED" -ne 0 ]; then
  echo "staging pipeline: FAILED (see $LOGS)"
  exit 1
fi
echo "staging pipeline: OK"
exit 0
