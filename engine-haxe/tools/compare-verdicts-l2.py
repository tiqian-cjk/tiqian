#!/usr/bin/env python3
"""Compare the per-test-case verdict records of the handwritten Kotlin engine
(legacy, the baseline) and one Haxe-to-Kotlin target bundle (the port).

Both sides emit one JSONL row per test case. A row carries the case id, the
runner name, the verdict, and, when the case failed, the failure message:

  legacy   {"id": "...", "name": "...", "verdict": "pass", "message": ""}
  port     {"id": "...", "name": "...", "verdict": "pass"}          (pass rows
           {"id": "...", "name": "...", "verdict": "fail", "message": "..."}
            drop the empty message field)

The id on the legacy side is the JUnit class name plus the method name; the id
on the port side is the Haxe module path plus the method name
(kotlincompiler/Compiler.hx:159 computes it as classType.module + "." + field).
The two are comparable as plain strings, so a difference in either set is a
finding.

The comparator reports three differences, in this order:

  1. id set difference      legacy-only ids and port-only ids, each grouped by
                            declaring class
  2. verdict difference     cases present on both sides whose verdict differs,
                            printed with both verdicts and both messages
  3. message difference     cases that failed on BOTH sides with different
                            message text (same text on both sides is agreement)

With --classify the script also attributes every legacy-only class to one of
three causes by reading the port source tree:

  port-class-without-test-metadata   the class exists in the port but its file
                                     carries no @:test marker on the class, so
                                     the target emits no test file for it
  port-class-renamed-or-merged       the class does not exist under that name,
                                     but a port class carries the same method
                                     set (the port renamed or merged it)
  no-port-class                      no port class carries those method names

Usage (from the worktree root):

  # 1. legacy side: run the handwritten Kotlin suite, then convert its JUnit
  #    XML into JSONL. GRADLE_USER_HOME and the Android SDK path are the two
  #    environment inputs the suite needs on this host.
  GRADLE_USER_HOME=/tmp/gradle-home ./gradlew :engine:jvmTest
  python3 engine-haxe/tools/compare-verdicts-l2.py \
      --legacy-xml engine/build/test-results/jvmTest \
      --emit-legacy-jsonl engine-haxe/out/test-results/legacy-jvmtest.jsonl

  # 2. port side: generate, compile and run the kotlin-f32 bundle. The timeout
  #    budget is required: four cases of the suite run longer than the 5000 ms
  #    default and would be reported as failures that the legacy side does not
  #    have (task t-muaw8dab-s5fm records the budget).
  export BORING_TEST_TIMEOUT_MS=180000
  haxe engine-haxe/targets/kotlin-f32.hxml
  kotlinc -J-Xmx6g $(find engine-haxe/out/kotlin-gen-f32 -name '*.kt') \
      -include-runtime -d /tmp/kf32-engine.jar
  kotlinc -J-Xmx6g -cp /tmp/kf32-engine.jar \
      $(find engine-haxe/out/kotlin-gen-f32-tests -name '*.kt') -d /tmp/kf32-tests.jar
  BORING_TEST_RESULTS=$PWD/engine-haxe/out/test-results/kotlin-f32.jsonl \
      java -cp /tmp/kf32-engine.jar:/tmp/kf32-tests.jar TestMainKt

  # 3. compare
  python3 engine-haxe/tools/compare-verdicts-l2.py \
      --legacy engine-haxe/out/test-results/legacy-jvmtest.jsonl \
      --port   engine-haxe/out/test-results/kotlin-f32.jsonl \
      --classify engine-haxe/src

Exit code 0 iff all three differences are empty.
"""

import argparse
import collections
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

# Gradle writes the Kotlin Multiplatform target name as a suffix on the test
# case name ("methodName[jvm]"); the class name attribute carries no suffix.
KMP_SUFFIX = re.compile(r"\[[^\]]*\]$")

CLASS_DECL = re.compile(r"^\s*(?:@[^\n]*\s+)?(?:final\s+|abstract\s+)?class\s+(\w+)", re.M)
TEST_META = re.compile(r"^\s*@:test\b", re.M)
TEST_FUNC = re.compile(r"@:test\s+public\s+static\s+function\s+(\w+)")


def load_jsonl(path):
    """Read one side's JSONL. Later rows for the same id replace earlier ones,
    and the first row order is kept so reports read in the producer's order."""
    rows = {}
    order = []
    for lineno, line in enumerate(Path(path).read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"{path}:{lineno}: not JSON: {exc}")
        if "id" not in row or "verdict" not in row:
            raise SystemExit(f"{path}:{lineno}: row needs id and verdict")
        if row["id"] not in rows:
            order.append(row["id"])
        rows[row["id"]] = row
    return rows, order


def read_junit_xml(path):
    """Convert Gradle JUnit XML into the same row shape the port emits.

    One row per <testcase>: id is classname + "." + method name with the KMP
    target suffix removed, verdict is pass unless the case carries <failure>,
    <error> or <skipped>, and message is the failure message attribute with
    the failure body appended when the attribute is empty.
    """
    path = Path(path)
    files = sorted(path.glob("*.xml")) if path.is_dir() else [path]
    if not files:
        raise SystemExit(f"{path}: no JUnit XML files")
    rows = []
    for xml in files:
        root = ET.parse(xml).getroot()
        suites = [root] if root.tag == "testsuite" else list(root.iter("testsuite"))
        for suite in suites:
            for case in suite.iter("testcase"):
                classname = case.get("classname") or ""
                name = KMP_SUFFIX.sub("", case.get("name") or "")
                if not classname:
                    continue
                verdict = "pass"
                message = ""
                for tag, label in (("failure", "fail"), ("error", "fail"), ("skipped", "skip")):
                    node = case.find(tag)
                    if node is None:
                        continue
                    verdict = label
                    message = (node.get("message") or "").strip()
                    if not message:
                        message = (node.text or "").strip()
                    break
                rows.append({
                    "id": f"{classname}.{name}",
                    "name": f"{classname}.{name}",
                    "verdict": verdict,
                    "message": message,
                })
    return rows


def write_jsonl(rows, path):
    out = Path(path)
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n")
    return out


def group_by_class(ids):
    groups = collections.OrderedDict()
    for case_id in ids:
        class_name, _, method = case_id.rpartition(".")
        groups.setdefault(class_name, []).append(method)
    return groups


def scan_port_classes(root):
    """Return {class name: (path, has test metadata, {emitted test method names})}.

    One Haxe module may declare several classes, so the body of each class is
    the text between its own declaration and the next one. The port carries two
    test shapes: a class whose methods each carry @:test (the target emits one
    test file and one id per method), and a class that only exposes a single
    entry function driven from tests/Main.hx (no @:test anywhere, so no target
    emits it).
    """
    classes = {}
    for source in Path(root).rglob("*.hx"):
        text = source.read_text(encoding="utf-8")
        marks = [(m.start(), m.group(1)) for m in CLASS_DECL.finditer(text)]
        for index, (position, name) in enumerate(marks):
            end = marks[index + 1][0] if index + 1 < len(marks) else len(text)
            body = text[position:end]
            prefix = text[max(0, position - 300):position]
            has_meta = bool(TEST_META.search(body)) or bool(TEST_META.search(prefix.rstrip().splitlines()[-1] if prefix.rstrip() else ""))
            classes[name] = (source, has_meta, set(TEST_FUNC.findall(body)))
    return classes


def classify_class(class_name, methods, port_classes):
    short = class_name.rpartition(".")[2]
    entry = port_classes.get(short)
    wanted = set(methods)
    if entry is not None:
        if not entry[1]:
            return "port-class-without-test-metadata"
        if not wanted <= entry[2]:
            return "port-class-without-those-methods"
        return "port-class-has-the-methods"
    for name, (path, has_meta, funcs) in port_classes.items():
        if has_meta and wanted <= funcs:
            return f"port-class-renamed-or-merged -> {name}"
    for name, (path, has_meta, funcs) in port_classes.items():
        if wanted <= funcs:
            return f"port-class-renamed-or-merged -> {name}"
    return "no-port-class"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--legacy", help="legacy verdict JSONL")
    parser.add_argument("--port", required=True, help="port verdict JSONL")
    parser.add_argument("--port-label", default=None, help="label for the port side in the report")
    parser.add_argument("--legacy-xml", help="JUnit XML file or directory to read instead of --legacy")
    parser.add_argument("--emit-legacy-jsonl", help="write the converted legacy rows here and continue")
    parser.add_argument("--classify", help="port source root (engine-haxe/src) to attribute legacy-only classes")
    parser.add_argument("--json", dest="json_out", help="write the three lists as JSON here")
    parser.add_argument("--max-lines", type=int, default=40,
                        help="ids printed per section before the report truncates (0 = no limit)")
    args = parser.parse_args(argv)

    if args.legacy_xml:
        rows = read_junit_xml(args.legacy_xml)
        if args.emit_legacy_jsonl:
            written = write_jsonl(rows, args.emit_legacy_jsonl)
            print(f"wrote {len(rows)} legacy rows to {written}")
        legacy, _ = load_jsonl(args.emit_legacy_jsonl) if args.emit_legacy_jsonl else ({r["id"]: r for r in rows}, None)
    elif args.legacy:
        legacy, _ = load_jsonl(args.legacy)
    else:
        parser.error("one of --legacy or --legacy-xml is required")

    port, _ = load_jsonl(args.port)
    label = args.port_label or Path(args.port).name

    legacy_ids = set(legacy)
    port_ids = set(port)
    legacy_only = [i for i in sorted(legacy_ids - port_ids)]
    port_only = [i for i in sorted(port_ids - legacy_ids)]
    common = [i for i in sorted(legacy_ids & port_ids)]

    verdict_diff = [
        (i, legacy[i].get("verdict"), port[i].get("verdict"),
         legacy[i].get("message", ""), port[i].get("message", ""))
        for i in common
        if legacy[i].get("verdict") != port[i].get("verdict")
    ]
    both_failed = [
        i for i in common
        if legacy[i].get("verdict") != "pass" and port[i].get("verdict") != "pass"
    ]
    message_diff = [
        (i, legacy[i].get("message", ""), port[i].get("message", ""))
        for i in both_failed
        if legacy[i].get("message", "") != port[i].get("message", "")
    ]

    legacy_fail = sum(1 for r in legacy.values() if r.get("verdict") != "pass")
    port_fail = sum(1 for r in port.values() if r.get("verdict") != "pass")

    def emit(lines, items, render):
        limit = args.max_lines
        shown = items if not limit else items[:limit]
        for item in shown:
            lines.append("    " + render(item))
        if limit and len(items) > limit:
            lines.append(f"    ... {len(items) - limit} more")

    report = []
    report.append(f"legacy rows {len(legacy)} ({legacy_fail} not pass)   "
                  f"{label} rows {len(port)} ({port_fail} not pass)   common {len(common)}")
    report.append("")
    report.append(f"[1] id set difference: legacy-only {len(legacy_only)}, "
                  f"{label}-only {len(port_only)}")
    report.append(f"  legacy-only grouped by class ({len(group_by_class(legacy_only))} classes):")
    for class_name, methods in group_by_class(legacy_only).items():
        cause = ""
        if args.classify:
            cause = "   [" + classify_class(class_name, methods, scan_port_classes(args.classify)) + "]"
        report.append(f"    {len(methods):4d}  {class_name}{cause}")
    report.append(f"  {label}-only grouped by class ({len(group_by_class(port_only))} classes):")
    for class_name, methods in group_by_class(port_only).items():
        report.append(f"    {len(methods):4d}  {class_name}")
    report.append("")
    report.append(f"[2] verdict differences: {len(verdict_diff)}")
    emit(report, verdict_diff, lambda row: f"{row[0]}  legacy={row[1]} port={row[2]}")
    report.append("")
    report.append(f"[3] both sides failed with different message: {len(message_diff)} "
                  f"(both sides failed {len(both_failed)} cases)")
    emit(report, message_diff, lambda row: f"{row[0]}\n        legacy: {row[1]!r}\n        port:   {row[2]!r}")

    print("\n".join(report))

    if args.json_out:
        payload = {
            "legacy_rows": len(legacy),
            "port_rows": len(port),
            "port_label": label,
            "common": len(common),
            "legacy_only": legacy_only,
            "port_only": port_only,
            "verdict_diff": [
                {"id": i, "legacy_verdict": lv, "port_verdict": pv,
                 "legacy_message": lm, "port_message": pm}
                for i, lv, pv, lm, pm in verdict_diff
            ],
            "message_diff": [
                {"id": i, "legacy_message": lm, "port_message": pm}
                for i, lm, pm in message_diff
            ],
        }
        if args.classify:
            port_classes = scan_port_classes(args.classify)
            payload["legacy_only_cause"] = {
                class_name: classify_class(class_name, methods, port_classes)
                for class_name, methods in group_by_class(legacy_only).items()
            }
        written = Path(args.json_out)
        written.parent.mkdir(parents=True, exist_ok=True)
        written.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
                           encoding="utf-8")
        print(f"wrote {written}")

    return 0 if not (legacy_only or port_only or verdict_diff or message_diff) else 1


if __name__ == "__main__":
    sys.exit(main())
