#!/usr/bin/env python3
"""Compare two Boring test-result jsonl files case by case (layer 3).

Layer 3 of the Tiqian port asks whether the Kotlin f64 target and the
TypeScript target of the same Haxe source agree per case. This script reads
the two jsonl files the two runtimes write when BORING_TEST_RESULTS names a
path (boring packages/compiler/runtime/TestCore.hx:229 emits one JSON object
per case) and applies the same comparison boring's own cross-target gate
applies, so a clean run here means the same thing as a clean run there:
boring/tools/test-consistency/Main.hx:249-282.

Comparison rules (unchanged from that gate):
  1. id set difference: an id present on one side only is a divergence.
  2. verdict mismatch: "pass" on one side, "fail" on the other.
  3. runner name mismatch: same verdict, different name field.
  4. failure message mismatch: reported only when BOTH sides failed.

Nothing else is normalized. Trailing whitespace, message wording and the
expected/actual block are compared as the runtime wrote them; the script
never rewrites a message or a verdict to make the two sides agree.

Usage:
  python3 engine-haxe/tools/compare-verdicts-l3.py <reference.jsonl> <actual.jsonl> \
      [--reference-name ts] [--actual-name kotlin-f64] \
      [--report FILE] [--json FILE] [--lists-dir DIR] \
      [--max-message-chars N] [--cluster]

Exit status: 0 when the two sides agree on every rule above, 1 when any
divergence exists, 2 on a usage or input error. Exit 1 is the expected
outcome for a run that still has work left, so treat the printed counts as
the reading and the status as the gate.
"""

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

# One field of a result line. Missing keys read as "" so a pass record and a
# fail record compare without special cases.
FIELDS = ("id", "name", "verdict", "message")

# Message text is echoed verbatim into the report. The default cap keeps a
# stack of long golden dumps readable; --max-message-chars 0 prints whole.
DEFAULT_MAX_MESSAGE_CHARS = 1200

# The first line of a canonical failure message names the test, so a cluster
# key that keeps only the line shape groups the same failure shape across
# cases without pretending the messages are equal.
ID_ECHO_RE = re.compile(r"^test failed: \S+$")


def read_records(path: Path, label: str) -> dict:
    """Read one jsonl file into id -> record, rejecting duplicate ids."""
    records = {}
    if not path.exists():
        print(f"error: {label}: no such file: {path}", file=sys.stderr)
        raise SystemExit(2)
    with path.open(encoding="utf-8") as handle:
        for number, line in enumerate(handle, 1):
            text = line.strip()
            if not text:
                continue
            try:
                parsed = json.loads(text)
            except json.JSONDecodeError as exc:
                print(f"error: {label}: {path}:{number}: {exc}", file=sys.stderr)
                raise SystemExit(2)
            case_id = parsed.get("id")
            if case_id is None or parsed.get("verdict") is None:
                print(f"error: {label}: {path}:{number}: no id or verdict", file=sys.stderr)
                raise SystemExit(2)
            if case_id in records:
                print(f"error: {label}: {path}:{number}: duplicate id {case_id}", file=sys.stderr)
                raise SystemExit(2)
            records[case_id] = {field: parsed.get(field, "") or "" for field in FIELDS}
    return records


def clip(text: str, limit: int) -> str:
    """Return text, cut to limit characters with an explicit marker."""
    if limit <= 0 or len(text) <= limit:
        return text
    head = text[:limit]
    return f"{head}\n[... {len(text) - limit} more characters; raise --max-message-chars to see them]"


def indent_block(label: str, text: str, limit: int) -> list:
    """Render one side of a divergence as indented lines."""
    if text == "":
        return [f"    {label}: (empty)"]
    body = clip(text, limit).splitlines() or [""]
    lines = [f"    {label}: {body[0]}"]
    lines.extend(f"      {extra}" for extra in body[1:])
    return lines


def cluster_key(record: dict) -> str:
    """Group failing cases by the shape of their message, longest line kept."""
    message = record.get("message", "")
    if message == "":
        return "(empty message)"
    lines = [line for line in message.splitlines() if line.strip()]
    if not lines:
        return "(empty message)"
    first = lines[0]
    if ID_ECHO_RE.match(first) and len(lines) > 1:
        return ID_ECHO_RE.sub("test failed: <id>", first) + " / " + lines[1].strip()[:80]
    return first.strip()[:120]


def module_of(case_id: str) -> str:
    """The package segment after org.tiqian, or the whole id when absent."""
    parts = case_id.split(".")
    if len(parts) >= 3 and parts[0] == "org" and parts[1] == "tiqian":
        return parts[2]
    return parts[0] if parts else case_id


def main(argv) -> int:
    parser = argparse.ArgumentParser(
        description="Compare two Boring test-result jsonl files case by case.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("reference", type=Path, help="reference side jsonl (the TS target here)")
    parser.add_argument("actual", type=Path, help="actual side jsonl (kotlin-f64 here)")
    parser.add_argument("--reference-name", default="reference", help="label for the reference side")
    parser.add_argument("--actual-name", default="actual", help="label for the actual side")
    parser.add_argument("--report", type=Path, help="write the full report to this path as well")
    parser.add_argument("--json", type=Path, help="write a machine-readable summary to this path")
    parser.add_argument("--lists-dir", type=Path, help="write one id list per divergence class into this directory")
    parser.add_argument("--max-message-chars", type=int, default=DEFAULT_MAX_MESSAGE_CHARS,
                        help="characters of each message kept in the report; 0 keeps all")
    parser.add_argument("--cluster", action="store_true",
                        help="add a diagnostic grouping of the failing cases by message shape")
    args = parser.parse_args(argv)

    ref = read_records(args.reference, args.reference_name)
    act = read_records(args.actual, args.actual_name)
    ref_ids = set(ref)
    act_ids = set(act)
    common = sorted(ref_ids & act_ids)
    only_ref = sorted(ref_ids - act_ids)
    only_act = sorted(act_ids - ref_ids)

    verdict_mismatch = []
    name_mismatch = []
    message_mismatch = []
    for case_id in common:
        left = ref[case_id]
        right = act[case_id]
        if left["verdict"] != right["verdict"]:
            verdict_mismatch.append(case_id)
            continue
        if left["name"] != right["name"]:
            name_mismatch.append(case_id)
        if left["verdict"] == "fail" and left["message"] != right["message"]:
            message_mismatch.append(case_id)

    out = []
    out.append(f"reference: {args.reference_name}  {args.reference}")
    out.append(f"actual:    {args.actual_name}  {args.actual}")
    out.append("")
    out.append("counts")
    out.append(f"  rows                     {args.reference_name}={len(ref)}  {args.actual_name}={len(act)}")
    out.append(f"  common ids               {len(common)}")
    out.append(f"  only in {args.reference_name:<16} {len(only_ref)}")
    out.append(f"  only in {args.actual_name:<16} {len(only_act)}")
    out.append(f"  verdict mismatch         {len(verdict_mismatch)}")
    out.append(f"  runner name mismatch     {len(name_mismatch)}")
    out.append(f"  failure message mismatch {len(message_mismatch)}  (of "
               f"{sum(1 for c in common if ref[c]['verdict'] == 'fail' and act[c]['verdict'] == 'fail')} "
               f"cases failed on both sides)")
    out.append(f"  failing cases            {args.reference_name}={sum(1 for r in ref.values() if r['verdict'] == 'fail')}"
               f"  {args.actual_name}={sum(1 for r in act.values() if r['verdict'] == 'fail')}")
    out.append("")

    limit = args.max_message_chars

    out.append(f"1. id set difference ({len(only_ref) + len(only_act)})")
    if not only_ref and not only_act:
        out.append("  none")
    for case_id in only_ref:
        out.append(f"  only in {args.reference_name}: {case_id}  verdict={ref[case_id]['verdict']}")
    for case_id in only_act:
        out.append(f"  only in {args.actual_name}: {case_id}  verdict={act[case_id]['verdict']}")
    out.append("")

    out.append(f"2. verdict mismatch ({len(verdict_mismatch)})")
    if not verdict_mismatch:
        out.append("  none")
    for case_id in verdict_mismatch:
        out.append(f"  {case_id}")
        out.append(f"    {args.reference_name}: {ref[case_id]['verdict']}")
        out.extend(indent_block(f"{args.reference_name} message", ref[case_id]["message"], limit))
        out.append(f"    {args.actual_name}: {act[case_id]['verdict']}")
        out.extend(indent_block(f"{args.actual_name} message", act[case_id]["message"], limit))
    out.append("")

    out.append(f"3. failure message mismatch, both sides failed ({len(message_mismatch)})")
    if not message_mismatch:
        out.append("  none")
    for case_id in message_mismatch:
        out.append(f"  {case_id}")
        out.extend(indent_block(f"{args.reference_name} message", ref[case_id]["message"], limit))
        out.extend(indent_block(f"{args.actual_name} message", act[case_id]["message"], limit))
    out.append("")

    out.append(f"4. runner name mismatch ({len(name_mismatch)})")
    if not name_mismatch:
        out.append("  none")
    for case_id in name_mismatch:
        out.append(f"  {case_id}")
        out.append(f"    {args.reference_name}: {ref[case_id]['name']}")
        out.append(f"    {args.actual_name}: {act[case_id]['name']}")
    out.append("")

    if args.cluster:
        out.append("5. diagnostic grouping of the actual-side failures by message shape")
        out.append("   (a reading aid for cause attribution; the criterion is section 2)")
        groups = defaultdict(list)
        for case_id, record in act.items():
            if record["verdict"] == "fail":
                groups[cluster_key(record)].append(case_id)
        if not groups:
            out.append("  none")
        for key in sorted(groups):
            ids = sorted(groups[key])
            modules = sorted({module_of(i) for i in ids})
            out.append(f"  [{len(ids)}] {key}")
            out.append(f"      modules: {', '.join(modules)}")
            for case_id in ids[:5]:
                out.append(f"      {case_id}")
            if len(ids) > 5:
                out.append(f"      ... {len(ids) - 5} more")
        out.append("")

    report = "\n".join(out) + "\n"
    sys.stdout.write(report)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(report, encoding="utf-8")
    if args.lists_dir:
        args.lists_dir.mkdir(parents=True, exist_ok=True)
        (args.lists_dir / "only-reference.txt").write_text("".join(i + "\n" for i in only_ref), encoding="utf-8")
        (args.lists_dir / "only-actual.txt").write_text("".join(i + "\n" for i in only_act), encoding="utf-8")
        (args.lists_dir / "verdict-mismatch.txt").write_text("".join(i + "\n" for i in verdict_mismatch), encoding="utf-8")
        (args.lists_dir / "message-mismatch.txt").write_text("".join(i + "\n" for i in message_mismatch), encoding="utf-8")
    if args.json:
        summary = {
            "reference": {"name": args.reference_name, "path": str(args.reference), "rows": len(ref),
                          "failures": sum(1 for r in ref.values() if r["verdict"] == "fail")},
            "actual": {"name": args.actual_name, "path": str(args.actual), "rows": len(act),
                       "failures": sum(1 for r in act.values() if r["verdict"] == "fail")},
            "common": len(common),
            "only_reference": only_ref,
            "only_actual": only_act,
            "verdict_mismatch": verdict_mismatch,
            "name_mismatch": name_mismatch,
            "message_mismatch": message_mismatch,
            "consistent": not (only_ref or only_act or verdict_mismatch or name_mismatch or message_mismatch),
        }
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    diverged = bool(only_ref or only_act or verdict_mismatch or name_mismatch or message_mismatch)
    return 1 if diverged else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
