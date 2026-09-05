#!/usr/bin/env python3
"""Compare produced trace files against golden traces.

Two modes:
  byte      Exact byte equality. Used when the producing backend runs the
            same arithmetic width as the golden generator (JVM f32), and for
            float-free classes on any backend.
  tolerance Structure-exact compare with numeric relative tolerance. Every
            non-numeric byte must match; numeric tokens may drift within the
            relative tolerance (default 1e-6, one f32 ulp magnitude).
            Truncation markers ~<len>#<hash> compare by marker kind only:
            the hash covers full operand text including drifting digits, so
            it can never converge across arithmetic widths.

Trace line grammar (engine TraceFormat):
  class: <Name>
  test: <fn>
  <event> key=value ... with values possibly quoted ('...') containing
  arbitrary text, numbers in plain decimal (scientific form is expanded
  by the renderer), 'NaN'/'Infinity'/'-Infinity' as quoted text, and
  <SimpleName>@identity as literal text.

Exception-name equivalence: on lines of the form "raises exception=<Name>",
the Kotlin builtin names IllegalArgumentException and NoSuchElementException
compare equal to their Tiqian-prefixed counterparts (EXCEPTION_NAME_ALIASES
below). This is a transition rule for the Haxe port: handwritten engine
files still throw the builtin names, while the port throws the Tiqian
classes ruled for generated code, and the goldens catch up one file at a
time as generated code replaces handwritten code. Every run reports how
many lines the rule matched (exception-alias=...); when no golden line
carries a builtin name any more, delete the rule.

Exit code 0 iff every compared class passes.
"""

import argparse
import re
import sys
from decimal import Decimal
from pathlib import Path

# Truncation marker: ~<full-length>#<fnv1a-32-hash>. Digits only.
MARKER_RE = re.compile(r"~\d+#\d+")
# Plain decimal number after renderer normalization (no exponent form).
NUMBER_RE = re.compile(r"-?\d+(?:\.\d+)?")

# Exception-name equivalence for "raises exception=<Name>" lines. Builtin
# name on one side compares equal to its Tiqian alias on the other; nothing
# else is forgiven (any other name difference still fails). See the module
# docstring for why this exists and when to delete it.
EXCEPTION_NAME_ALIASES = {
    "IllegalArgumentException": "TiqianIllegalArgumentException",
    "NoSuchElementException": "TiqianNoSuchElementException",
}

_EXCEPTION_LINE_RE = re.compile(r"^(raises exception=)([A-Za-z0-9_]+)(.*)$")


def normalize_exception_names(line: str) -> str:
    """Map a builtin exception name to its Tiqian alias on raises lines."""
    m = _EXCEPTION_LINE_RE.match(line)
    if m is None:
        return line
    return m.group(1) + EXCEPTION_NAME_ALIASES.get(m.group(2), m.group(2)) + m.group(3)

# Longest-match tokenizer: marker, then number, else one text char.
# The truncation stamp's hash is eight lowercase hex digits; a hash whose
# digits happen to be all decimal still matches, so the hex class is
# required for every stamp to tokenize as a marker.
_TOKEN_RE = re.compile(r"(~\d+#[0-9a-f]+)|(-?\d+(?:\.\d+)?)")

# Kotlin List joins printed elements with ", " while the stage-1 Haxe array
# print joins with ",". Synthesized record members match the Kotlin field
# order and names, so the only difference is the separator; collapse it on
# both sides before tokenizing (tolerance mode only).
_COLLECTION_JOIN_RE = re.compile(r", ")


def normalize_collection_joins(line: str) -> str:
    """Treat the ", " list join and the "," array join as equal."""
    return _COLLECTION_JOIN_RE.sub(",", line)


# The render cap cuts operand text at a fixed character count, so two
# renders whose numeric tokens differ in digit width (f32 artifacts such as
# 0.8000001 vs a clean f64 0.8) cut at different fields and leave different
# partial tokens before the truncation stamp. The stamp already compares by
# marker kind only, so the partial token is cap-position noise; drop it back
# to the last separator, a comma or the "=" of a cut field
# (tolerance mode only).
_PARTIAL_TOKEN_STAMP_RE = re.compile(r"([,=])[^,=\[\]()]*~\d+#[0-9a-f]+")


def normalize_truncation_stamps(line: str) -> str:
    """Replace each partial-token-plus-stamp region with a bare marker."""
    return _PARTIAL_TOKEN_STAMP_RE.sub(lambda m: m.group(1) + "~", line)

MAX_REPORTED_LINES = 12


def tokenize(line: str):
    """Split a line into (kind, value) tokens.

    kind is 'marker', 'number', or 'text' (single char for text runs,
    merged later by the caller only via sequence position).
    """
    tokens = []
    pos = 0
    n = len(line)
    while pos < n:
        ch = line[pos]
        if ch == "~" or ch == "-" or ch.isdigit():
            m = _TOKEN_RE.match(line, pos)
            if m:
                if m.group(1) is not None:
                    tokens.append(("marker", m.group(1)))
                else:
                    tokens.append(("number", m.group(2)))
                pos = m.end()
                continue
        tokens.append(("text", ch))
        pos += 1
    # Merge adjacent text tokens into runs for fewer comparisons.
    merged = []
    for kind, value in tokens:
        if merged and merged[-1][0] == "text" and kind == "text":
            merged[-1] = ("text", merged[-1][1] + value)
        else:
            merged.append((kind, value))
    return merged


def numbers_close(a: str, b: str, tol: Decimal) -> bool:
    """Relative-tolerance numeric compare on decimal token text."""
    da, db = Decimal(a), Decimal(b)
    if da == db:
        return True
    if da == 0 or db == 0:
        # Zero must match zero exactly; sign of zero is not rendered.
        return False
    diff = abs(da - db)
    scale = max(abs(da), abs(db))
    return (diff / scale) <= tol


def compare_lines(golden_line: str, actual_line: str, tol: Decimal):
    """Return None if lines match, else a human-readable mismatch reason."""
    g_tokens = tokenize(golden_line)
    a_tokens = tokenize(actual_line)
    if len(g_tokens) != len(a_tokens):
        return (
            f"token count {len(g_tokens)} vs {len(a_tokens)}\n"
            f"  golden: {golden_line}\n  actual: {actual_line}"
        )
    for (gk, gv), (ak, av) in zip(g_tokens, a_tokens):
        if gk != ak:
            return (
                f"token kind {gk}:{gv!r} vs {ak}:{av!r}\n"
                f"  golden: {golden_line}\n  actual: {actual_line}"
            )
        if gk == "text" and gv != av:
            return (
                f"text {gv!r} vs {av!r}\n"
                f"  golden: {golden_line}\n  actual: {actual_line}"
            )
        if gk == "number" and not numbers_close(gv, av, tol):
            return (
                f"number {gv} vs {av} beyond tolerance {tol}\n"
                f"  golden: {golden_line}\n  actual: {actual_line}"
            )
        # marker: kind equality is enough; contents stripped by design.
    return None


def compare_class(golden_path: Path, actual_path: Path, mode: str, tol: Decimal):
    """Return (ok, failures, alias_count).

    failures lists diff details. alias_count is the number of lines where
    EXCEPTION_NAME_ALIASES changed a side before the lines matched; lines
    that pass without the map, or fail, are not counted.
    """
    if not actual_path.is_file():
        return False, [f"missing actual file: {actual_path}"], 0
    golden_bytes = golden_path.read_bytes()
    actual_bytes = actual_path.read_bytes()
    if mode == "byte":
        if golden_bytes == actual_bytes:
            return True, [], 0
        g_lines = golden_bytes.decode("utf-8", errors="replace").splitlines()
        a_lines = actual_bytes.decode("utf-8", errors="replace").splitlines()
        failures = []
        alias_count = 0
        for i in range(max(len(g_lines), len(a_lines))):
            g_raw = g_lines[i] if i < len(g_lines) else "<missing>"
            a_raw = a_lines[i] if i < len(a_lines) else "<missing>"
            if g_raw == a_raw:
                continue
            g = normalize_exception_names(g_raw)
            a = normalize_exception_names(a_raw)
            if g == a and (g != g_raw or a != a_raw):
                # A differing raw line passes only when the alias map
                # bridges the whole difference; anything else stays a
                # byte failure.
                alias_count += 1
                continue
            failures.append(f"line {i + 1}:\n  golden: {g_raw}\n  actual: {a_raw}")
            if len(failures) >= MAX_REPORTED_LINES:
                break
        if not failures and len(g_lines) == len(a_lines):
            failures.append("bytes differ (line split identical; check endings)")
        return (not failures), failures, alias_count
    # tolerance mode
    g_lines = golden_bytes.decode("utf-8", errors="replace").splitlines()
    a_lines = actual_bytes.decode("utf-8", errors="replace").splitlines()
    if len(g_lines) != len(a_lines):
        return False, [
            f"line count {len(g_lines)} vs {len(a_lines)}\n"
            f"  golden tail: {g_lines[len(a_lines):][:3] if len(g_lines) > len(a_lines) else ''}"
            f"  actual tail: {a_lines[len(g_lines):][:3] if len(a_lines) > len(a_lines) else ''}"
        ], 0
    failures = []
    alias_count = 0
    for i, (g_raw, a_raw) in enumerate(zip(g_lines, a_lines)):
        g = normalize_truncation_stamps(normalize_collection_joins(normalize_exception_names(g_raw)))
        a = normalize_truncation_stamps(normalize_collection_joins(normalize_exception_names(a_raw)))
        reason = compare_lines(g, a, tol)
        if reason is None:
            if g != g_raw or a != a_raw:
                alias_count += 1
            continue
        failures.append(f"line {i + 1}: {reason}")
        if len(failures) >= MAX_REPORTED_LINES:
            break
    return (not failures), failures, alias_count


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("golden_dir", type=Path)
    parser.add_argument("actual_dir", type=Path)
    parser.add_argument(
        "--mode", choices=("byte", "tolerance"), default="byte",
        help="byte: exact equality; tolerance: numeric relative tolerance",
    )
    parser.add_argument(
        "--tol", type=Decimal, default=Decimal("1e-6"),
        help="relative tolerance for numeric tokens (tolerance mode)",
    )
    parser.add_argument(
        "--classes",
        help="comma-separated class names to compare (default: all goldens)",
    )
    parser.add_argument(
        "--report", type=Path, help="write full failure detail to this file",
    )
    args = parser.parse_args()

    golden_dir: Path = args.golden_dir
    actual_dir: Path = args.actual_dir
    if args.classes:
        names = [c.strip() for c in args.classes.split(",") if c.strip()]
    else:
        names = sorted(p.stem for p in golden_dir.glob("*.txt"))
    if not names:
        print("no golden files to compare", file=sys.stderr)
        return 2

    passed, failed = [], []
    detail_sections = []
    total_alias = 0
    for name in names:
        golden_path = golden_dir / f"{name}.txt"
        if not golden_path.is_file():
            failed.append(name)
            detail_sections.append(f"== {name} ==\nmissing golden file: {golden_path}")
            continue
        ok, failures, alias_count = compare_class(
            golden_path, actual_dir / f"{name}.txt", args.mode, args.tol
        )
        total_alias += alias_count
        if ok:
            passed.append(name)
        else:
            failed.append(name)
            detail_sections.append(f"== {name} ==\n" + "\n".join(failures))

    print(f"mode={args.mode} tol={args.tol} classes={len(names)} "
          f"pass={len(passed)} fail={len(failed)}")
    print(f"exception-alias={total_alias} lines matched via EXCEPTION_NAME_ALIASES "
          f"(0 expected once no golden carries a builtin exception name)")
    if failed:
        print("failed:", ", ".join(failed))
    if args.report and detail_sections:
        args.report.write_text("\n\n".join(detail_sections) + "\n", encoding="utf-8")
        print(f"failure detail: {args.report}")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
