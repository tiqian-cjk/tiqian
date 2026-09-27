#!/usr/bin/env python3
"""Compare two per-class test-trace directories produced by two double-precision
(binary64) targets of the same Haxe source.

Both sides of this comparison run IEEE-754 binary64 arithmetic, so the expected
result is byte equality after the exception-name alias map: the same Haxe
expression, rendered by two code generators, must produce the same text. A
difference is therefore a finding, not noise, and every difference is reported
with the full text of both lines.

The comparator classifies each differing line pair on a normalization ladder so
the report separates "the two sides agree, they only spell it differently" from
"the two sides disagree about the value":

  L0 exact           byte-identical
  L1 exception-alias equal after the exception-name alias map
                     (compare-traces.py, the single source of truth)
  L2 join-separator  equal after collapsing the ", " / "," collection join
                     (Kotlin List prints ", ", the Haxe bundle prints ",")
  L3 truncation      equal after replacing every truncation stamp
                     ~<len>#<hash> with a bare "~" (the stamp covers operand
                     text the renderer cut, so it carries no comparable value)
  NUMERIC            same text except numeric tokens; the numbers differ
  STRUCTURAL         everything else: field order, missing field, extra line
  LINE-COUNT         the two classes do not have the same number of lines

Usage (from the worktree root):

  python3 engine-haxe/tools/compare-f64-traces.py <reference-dir> <actual-dir> \
      [--classes A,B] [--max-lines N] [--report FILE] [--json FILE]

Exit code 0 iff every comparable class is L0/L1 identical.

See engine-haxe/tools/f64-trace-compare.sh for the pipeline that produces the two
directories this script consumes.
"""

import argparse
import importlib.util
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# The exception-name alias map lives in compare-traces.py; import it instead of
# copying the table so the two tools can never disagree about what "alias" means.
_spec = importlib.util.spec_from_file_location("compare_traces", HERE / "compare-traces.py")
_ct = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_ct)
normalize_exception_names = _ct.normalize_exception_names

# Kotlin List joins printed elements with ", ", the Haxe array print joins with
# ",". Synthesized record members match the Kotlin field order and names, so the
# separator is the only difference (layer-1 finding, kept here as a ladder step
# rather than a silent normalization).
_JOIN_RE = re.compile(r", ")
# Truncation stamp: ~<full-length>#<fnv1a-32-hash>.
_STAMP_RE = re.compile(r"~\d+#[0-9a-f]+")
# Longest-match tokenizer: stamp, number, else one text char.
_TOKEN_RE = re.compile(r"(~\d+#[0-9a-f]+)|(-?\d+(?:\.\d+)?)")


def collapse_joins(line: str) -> str:
    return _JOIN_RE.sub(",", line)


def collapse_stamps(line: str) -> str:
    return _STAMP_RE.sub("~", line)


def tokenize(line: str):
    """Split into [("marker"|"number"|"text", value)] with adjacent text merged."""
    tokens = []
    pos, n = 0, len(line)
    while pos < n:
        ch = line[pos]
        if ch in "~-" or ch.isdigit():
            m = _TOKEN_RE.match(line, pos)
            if m:
                tokens.append(("marker" if m.group(1) else "number", m.group(0)))
                pos = m.end()
                continue
        tokens.append(("text", ch))
        pos += 1
    merged = []
    for kind, value in tokens:
        if merged and merged[-1][0] == "text" and kind == "text":
            merged[-1] = ("text", merged[-1][1] + value)
        else:
            merged.append((kind, value))
    return merged


def numeric_only(reference: str, actual: str) -> bool:
    """True when the two lines differ only in the value of numeric tokens."""
    rt, at = tokenize(reference), tokenize(actual)
    if len(rt) != len(at):
        return False
    seen_number = False
    for (rk, rv), (ak, av) in zip(rt, at):
        if rk != ak:
            return False
        if rk != "number":
            if rv != av:
                return False
        elif rv != av:
            seen_number = True
    return seen_number


def classify(reference: str, actual: str):
    """Return (level, note) for one differing line pair."""
    if reference == actual:
        return "L0", ""
    r_alias = normalize_exception_names(reference)
    a_alias = normalize_exception_names(actual)
    if r_alias == a_alias:
        return "L1", "exception name alias only"
    if collapse_joins(r_alias) == collapse_joins(a_alias):
        return "L2", 'collection join ", " vs "," only'
    if collapse_stamps(collapse_joins(r_alias)) == collapse_stamps(collapse_joins(a_alias)):
        return "L3", "truncation stamp only (difference lies inside cut operand text)"
    if numeric_only(r_alias, a_alias):
        return "NUMERIC", "numeric tokens differ"
    return "STRUCTURAL", ""


def first_diff_offset(a: str, b: str) -> int:
    for i in range(min(len(a), len(b))):
        if a[i] != b[i]:
            return i
    return min(len(a), len(b))


def compare_class(ref_path: Path, act_path: Path, max_lines: int):
    ref_lines = ref_path.read_text(encoding="utf-8", errors="replace").splitlines()
    act_lines = act_path.read_text(encoding="utf-8", errors="replace").splitlines()
    result = {
        "reference_lines": len(ref_lines),
        "actual_lines": len(act_lines),
        "differences": [],
        "levels": {},
    }
    if len(ref_lines) != len(act_lines):
        result["levels"]["LINE-COUNT"] = 1
    for i in range(max(len(ref_lines), len(act_lines))):
        r = ref_lines[i] if i < len(ref_lines) else "<missing line>"
        a = act_lines[i] if i < len(act_lines) else "<missing line>"
        if r == a:
            continue
        level, note = classify(r, a)
        result["levels"][level] = result["levels"].get(level, 0) + 1
        if len(result["differences"]) < max_lines:
            result["differences"].append({
                "line": i + 1,
                "level": level,
                "note": note,
                "first_diff_char": first_diff_offset(r, a),
                "reference": r,
                "actual": a,
            })
    return result


def worst_level(levels) -> str:
    for level in ("LINE-COUNT", "STRUCTURAL", "NUMERIC", "L3", "L2", "L1"):
        if levels.get(level):
            return level
    return "L0"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("reference_dir", type=Path,
                        help="trace directory of the reference side")
    parser.add_argument("actual_dir", type=Path,
                        help="trace directory of the side under test")
    parser.add_argument("--reference-name", default=None,
                        help="label for the reference side in the report")
    parser.add_argument("--actual-name", default=None,
                        help="label for the side under test in the report")
    parser.add_argument("--classes", help="comma-separated class subset")
    parser.add_argument("--max-lines", type=int, default=3,
                        help="differing lines to print per class (default 3)")
    parser.add_argument("--report", type=Path, help="write the full text report here")
    parser.add_argument("--json", type=Path, help="write a machine-readable summary here")
    args = parser.parse_args()

    ref_name = args.reference_name or args.reference_dir.name
    act_name = args.actual_name or args.actual_dir.name

    def stems(directory: Path):
        return {p.stem for p in directory.glob("*.txt")}

    ref_classes, act_classes = stems(args.reference_dir), stems(args.actual_dir)
    common = sorted(ref_classes & act_classes)
    if args.classes:
        wanted = [c.strip() for c in args.classes.split(",") if c.strip()]
        common = [c for c in common if c in wanted]
    only_reference = sorted(ref_classes - act_classes)
    only_actual = sorted(act_classes - ref_classes)

    identical_L0, identical_L1, differing = [], [], []
    detail = []
    level_totals = {}
    for name in common:
        res = compare_class(args.reference_dir / f"{name}.txt",
                            args.actual_dir / f"{name}.txt", args.max_lines)
        level = worst_level(res["levels"])
        for k, v in res["levels"].items():
            level_totals[k] = level_totals.get(k, 0) + v
        if level == "L0":
            identical_L0.append(name)
            continue
        if level == "L1":
            identical_L1.append(name)
            continue
        entry = {"class": name, "worst_level": level, "levels": res["levels"],
                 "reference_lines": res["reference_lines"],
                 "actual_lines": res["actual_lines"],
                 "differences": res["differences"]}
        differing.append(entry)
        detail.append(entry)

    # ---------------------------------------------------------------- report
    out = []
    out.append(f"reference : {ref_name}  ({args.reference_dir})  {len(ref_classes)} classes")
    out.append(f"actual    : {act_name}  ({args.actual_dir})  {len(act_classes)} classes")
    out.append("")
    out.append(f"comparable classes      : {len(common)}")
    out.append(f"byte-identical (L0)     : {len(identical_L0)}")
    out.append(f"alias-identical (L1)    : {len(identical_L1)}")
    out.append(f"differing               : {len(differing)}")
    out.append(f"only on reference side  : {len(only_reference)}"
               + (f"  {', '.join(only_reference)}" if only_reference else ""))
    out.append(f"only on actual side     : {len(only_actual)}"
               + (f"  {', '.join(only_actual)}" if only_actual else ""))
    out.append("")
    out.append("differing lines by classification: "
               + (", ".join(f"{k}={v}" for k, v in sorted(level_totals.items())) or "none"))
    out.append("")
    if differing:
        out.append("differing classes (worst classification, differing-line count):")
        for entry in sorted(differing, key=lambda e: (-len(e["differences"]), e["class"])):
            counts = ", ".join(f"{k}={v}" for k, v in sorted(entry["levels"].items()))
            out.append(f"  {entry['worst_level']:<11} {entry['class']:<52} {counts}")
    out.append("")
    if detail:
        out.append("=" * 78)
        out.append("per-class detail (first %d differing lines, full text)" % args.max_lines)
        out.append("=" * 78)
        for entry in sorted(detail, key=lambda e: e["class"]):
            out.append("")
            out.append(f"--- {entry['class']}  worst={entry['worst_level']}  "
                       f"reference-lines={entry['reference_lines']} "
                       f"actual-lines={entry['actual_lines']}")
            for d in entry["differences"]:
                out.append(f"  line {d['line']}  [{d['level']}] {d['note']}  "
                           f"first-diff-char={d['first_diff_char']}")
                out.append(f"    REF: {d['reference']}")
                out.append(f"    ACT: {d['actual']}")

    text = "\n".join(out) + "\n"
    print(text, end="")
    if args.report:
        args.report.write_text(text, encoding="utf-8")

    if args.json:
        args.json.write_text(json.dumps({
            "reference": {"name": ref_name, "dir": str(args.reference_dir),
                          "classes": len(ref_classes)},
            "actual": {"name": act_name, "dir": str(args.actual_dir),
                       "classes": len(act_classes)},
            "comparable": len(common),
            "identical_L0": identical_L0,
            "identical_L1": identical_L1,
            "only_reference": only_reference,
            "only_actual": only_actual,
            "differing": [{k: v for k, v in e.items() if k != "differences"} for e in differing],
            "max_lines": args.max_lines,
        }, indent=2, ensure_ascii=False), encoding="utf-8")

    return 0 if not differing else 1


if __name__ == "__main__":
    sys.exit(main())
