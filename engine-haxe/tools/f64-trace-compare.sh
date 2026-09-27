#!/usr/bin/env bash
# Build both sides of the layer-3 trace comparison and diff them.
#
# Layer 3 compares two targets that both run IEEE-754 binary64 arithmetic and
# are generated from the same Haxe source: the Kotlin f64 target
# (engine-haxe/targets/kotlin-f64.hxml) and a double-precision JavaScript
# reference. Both sides must be built from ONE source revision, so this script
# always rebuilds the requested sides and records the revision it used.
#
# Directory layout. TestTracePlatform.hx writes per-class trace files into
# engine-haxe/out/kotlin-traces for the Kotlin target and into
# engine-haxe/out/haxe-traces for every other target, so the Kotlin side and
# the JavaScript side never share a directory, but the Haxe/JS bundle and the
# TypeScript target DO share haxe-traces. Each step therefore copies its
# product into engine-haxe/out/compare/<side> before the next step can
# overwrite the shared directory.
#
# Usage (from the worktree root):
#
#   bash engine-haxe/tools/f64-trace-compare.sh all
#   bash engine-haxe/tools/f64-trace-compare.sh kotlin js compare
#   bash engine-haxe/tools/f64-trace-compare.sh compare
#
# Steps:
#   kotlin    generate + compile + run the Kotlin f64 test bundle,
#             copy its traces to out/compare/kotlin-f64
#   js        generate + run the Haxe/JS test bundle (tests/Main.hx) with
#             tests/compile.hxml (float-precision=f32, the layer-1 f32 oracle
#             build), copy its traces to out/compare/js-bundle
#   jsf64     generate + run the Haxe/JS test bundle with
#             tests/compile-js-f64.hxml, which is compile.hxml without the
#             float-precision define; copy its traces to out/compare/js-bundle-f64.
#             THIS is the double-precision reference layer 3 compares against:
#             with the define present, boring/samples/std/RecordShape.hx:212
#             prints every Float record field as its f32-shortest decimal, so
#             the f32-oracle bundle hides the binary64 digits under comparison.
#   ts        run the TypeScript target's generated bun test tree,
#             copy its traces to out/compare/ts-target
#   compare   diff out/compare/js-bundle-f64 against out/compare/kotlin-f64,
#             then report the f32-oracle bundle's diff count for contrast
#
# Environment: the nix store paths below are the ones the worktree is built
# with; HAXELIB_PATH must point at the worktree's .haxelib.

set -u
export PATH=/nix/store/98pb92k7pi6g5cifmg872jn18kghaxw5-haxe-4.3.7/bin:/nix/store/rqx09a40a82di944xi6ydjyzx632av28-kotlin-2.4.10/bin:/nix/store/0a9l8lf8394msppsna27y58f8ljqyifn-openjdk-25.0.4+7/bin:/home/losses/.bun/bin:$PATH
export BORING_TEST_TIMEOUT_MS=180000

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export HAXELIB_PATH="$ROOT/.haxelib"

KOTLINC=/nix/store/rqx09a40a82di944xi6ydjyzx632av28-kotlin-2.4.10/bin/kotlinc
JAVA=/nix/store/0a9l8lf8394msppsna27y58f8ljqyifn-openjdk-25.0.4+7/bin/java
OUT=engine-haxe/out/compare
KOTLIN_ENGINE_JAR=/tmp/f64cmp-engine.jar
KOTLIN_TESTS_JAR=/tmp/f64cmp-tests.jar

mkdir -p "$OUT"

record_revision() {
  {
    echo "revision: $(git rev-parse HEAD)"
    echo "recorded: $(date -Is)"
    echo "--- git status --porcelain ---"
    git status --porcelain
  } > "$OUT/revision.txt"
}

step_kotlin() {
  echo "=== kotlin: generate + compile + run (f64) $(date -Is)"
  rm -rf engine-haxe/out/kotlin-gen-f64 engine-haxe/out/kotlin-gen-f64-tests engine-haxe/out/kotlin-traces
  haxe engine-haxe/targets/kotlin-f64.hxml > "$OUT/gen-kotlin.log" 2>&1
  echo "GEN-RC=$? kt-files=$(find engine-haxe/out/kotlin-gen-f64 -name '*.kt' | wc -l)"
  "$KOTLINC" -J-Xmx6g $(find engine-haxe/out/kotlin-gen-f64 -name '*.kt') \
      -include-runtime -d "$KOTLIN_ENGINE_JAR" > "$OUT/kotlinc-engine.log" 2>&1
  echo "ENGINE-RC=$? errors=$(grep -ac ' error: ' "$OUT/kotlinc-engine.log")"
  "$KOTLINC" -J-Xmx6g -cp "$KOTLIN_ENGINE_JAR" \
      $(find engine-haxe/out/kotlin-gen-f64-tests -name '*.kt') \
      -d "$KOTLIN_TESTS_JAR" > "$OUT/kotlinc-tests.log" 2>&1
  echo "TESTS-RC=$? errors=$(grep -ac ' error: ' "$OUT/kotlinc-tests.log")"
  rm -f engine-haxe/out/test-results/kotlin-f64.jsonl
  BORING_TEST_RESULTS="$ROOT/engine-haxe/out/test-results/kotlin-f64.jsonl" \
      "$JAVA" -cp "$KOTLIN_ENGINE_JAR:$KOTLIN_TESTS_JAR" TestMainKt \
      > "$OUT/kotlin-f64-run.log" 2>&1
  echo "RUN-RC=$? traces=$(ls engine-haxe/out/kotlin-traces 2>/dev/null | wc -l)"
  report_jsonl engine-haxe/out/test-results/kotlin-f64.jsonl "kotlin-f64"
  rm -rf "$OUT/kotlin-f64"
  cp -a engine-haxe/out/kotlin-traces "$OUT/kotlin-f64"
  echo "saved=$OUT/kotlin-f64 classes=$(ls "$OUT/kotlin-f64" | wc -l)"
}

step_js() {
  echo "=== js: generate + run the Haxe/JS bundle $(date -Is)"
  haxe engine-haxe/tests/compile.hxml > "$OUT/gen-js.log" 2>&1
  echo "GEN-RC=$?"
  rm -f engine-haxe/out/haxe-traces/*.txt
  bun engine-haxe/out/haxe-tests.js > "$OUT/js-run.log" 2>&1
  echo "RUN-RC=$? FAIL-lines=$(grep -c '^FAIL' "$OUT/js-run.log") traces=$(ls engine-haxe/out/haxe-traces/*.txt 2>/dev/null | wc -l)"
  rm -rf "$OUT/js-bundle"
  cp -a engine-haxe/out/haxe-traces "$OUT/js-bundle"
  echo "saved=$OUT/js-bundle classes=$(ls "$OUT/js-bundle" | wc -l)"
}

step_jsf64() {
  echo "=== jsf64: generate + run the Haxe/JS bundle in the binary64 lane $(date -Is)"
  haxe engine-haxe/tests/compile-js-f64.hxml > "$OUT/gen-js-f64.log" 2>&1
  echo "GEN-RC=$?"
  rm -f engine-haxe/out/haxe-traces/*.txt
  bun engine-haxe/out/haxe-tests-f64.js > "$OUT/js-f64-run.log" 2>&1
  echo "RUN-RC=$? FAIL-lines=$(grep -c '^FAIL' "$OUT/js-f64-run.log") traces=$(ls engine-haxe/out/haxe-traces/*.txt 2>/dev/null | wc -l)"
  rm -rf "$OUT/js-bundle-f64"
  cp -a engine-haxe/out/haxe-traces "$OUT/js-bundle-f64"
  echo "saved=$OUT/js-bundle-f64 classes=$(ls "$OUT/js-bundle-f64" | wc -l)"
}

step_ts() {
  echo "=== ts: run the TypeScript target's bun test tree $(date -Is)"
  rm -f engine-haxe/out/haxe-traces/*.txt
  BORING_TEST_RESULTS="$ROOT/engine-haxe/out/test-results/ts-target.jsonl" \
      bun test engine-haxe/out/ts-gen-tests > "$OUT/ts-run.log" 2>&1
  echo "RUN-RC=$? traces=$(ls engine-haxe/out/haxe-traces/*.txt 2>/dev/null | wc -l)"
  report_jsonl engine-haxe/out/test-results/ts-target.jsonl "ts-target"
  rm -rf "$OUT/ts-target"
  cp -a engine-haxe/out/haxe-traces "$OUT/ts-target"
  echo "saved=$OUT/ts-target classes=$(ls "$OUT/ts-target" | wc -l)"
}

report_jsonl() {
  local path="$1" label="$2"
  [ -f "$path" ] || { echo "  ($label: no jsonl at $path)"; return; }
  python3 - "$path" "$label" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
bad = [r["id"] for r in rows if r.get("verdict") != "pass"]
print("  BORING %s: %d rows, %d failures" % (sys.argv[2], len(rows), len(bad)))
for i in bad:
    print("     FAIL", i)
PY
}

step_compare() {
  echo "=== compare $(date -Is)"
  python3 engine-haxe/tools/compare-f64-traces.py \
      "$OUT/js-bundle-f64" "$OUT/kotlin-f64" \
      --reference-name haxe-js-bundle-f64 --actual-name kotlin-f64 \
      --max-lines 4 \
      --report "$OUT/f64-vs-jsf64-report.txt" \
      --json "$OUT/f64-vs-jsf64-summary.json"
  echo "COMPARE-RC=$?"
  echo "full report: $OUT/f64-vs-jsf64-report.txt"
  if [ -d "$OUT/js-bundle" ]; then
    echo "--- contrast: the f32-oracle bundle (tests/compile.hxml) against the same kotlin side"
    python3 engine-haxe/tools/compare-f64-traces.py \
        "$OUT/js-bundle" "$OUT/kotlin-f64" \
        --reference-name haxe-js-bundle-f32define --actual-name kotlin-f64 \
        --max-lines 2 \
        --report "$OUT/f64-vs-jsf32define-report.txt" \
        --json "$OUT/f64-vs-jsf32define-summary.json" | sed -n '1,12p'
    echo "CONTRAST-RC=$?"
  fi
}

record_revision

if [ $# -eq 0 ]; then set -- all; fi
for step in "$@"; do
  case "$step" in
    all) step_kotlin; step_js; step_jsf64; step_compare ;;
    kotlin) step_kotlin ;;
    js) step_js ;;
    jsf64) step_jsf64 ;;
    ts) step_ts ;;
    compare) step_compare ;;
    *) echo "unknown step: $step" >&2; exit 2 ;;
  esac
done
echo "=== done $(date -Is)"
