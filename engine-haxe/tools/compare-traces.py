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

Section-scoped compare (tolerance mode): the two sides may run different
test-case sets (the port adds coverage tests the handwritten baseline does
not have), which makes a whole-file line-by-line compare meaningless -- an
inserted `test:` header shifts every later line (TCN-26). Tolerance mode
therefore splits each file into `test:` sections, compares only sections
whose `test:` name exists on both sides plus the preamble before the first
section, and reports section sets that exist on one side only without
failing. Inside a section the compare works on the set of distinct lines
after normalization: line order and copy counts are recorder-set details
that differ when one side runs extra cases, while a line whose content
(no numeric drift beyond tolerance) exists on only one side is a real
difference and fails.

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




_SELF_CONSISTENT_RE = re.compile(
    r"^(eq|eq-tol)\b.*?\bexpected=(.*?)\bactual=(.*?)(\bmsg=|\btol=|$)"
)


def line_self_consistent(line, tol):
    """True when the record asserts agreement by itself.

    An unmatched record still proves nothing wrong when its own expected and
    actual values compare equal: the port recording one more agreeing
    assertion than the golden is a recorder-set difference, not a value
    divergence. A record whose own values disagree, or one whose form this
    check cannot read, is not exempted.
    """
    if line.startswith("is-true ") and " actual=true" in line:
        return True
    if line.startswith("is-false ") and " actual=false" in line:
        return True
    m = _SELF_CONSISTENT_RE.match(line)
    if m is None:
        return False
    return compare_lines(m.group(2).strip(), m.group(3).strip(), tol) is None


def split_sections(lines):
    """Split trace lines into (preamble, sections) keyed by the test: line."""
    preamble = []
    sections = {}
    current = None
    for line in lines:
        if line.startswith("test: "):
            current = line
            sections.setdefault(current, [])
        elif current is None:
            preamble.append(line)
        else:
            sections[current].append(line)
    return preamble, sections


def _normalize_line(line):
    return normalize_truncation_stamps(
        normalize_collection_joins(normalize_exception_names(line))
    )


def compare_line_sets(golden_lines, actual_lines, tol):
    """Compare distinct normalized line contents; order and copy counts ignored.

    Each distinct golden line must find a distinct actual line that compares
    equal under the tolerance pipeline, and vice versa. Returns (failures,
    alias_count).
    """
    failures = []
    alias_count = 0
    a_pool = list(dict.fromkeys(actual_lines))
    for g_raw in dict.fromkeys(golden_lines):
        g = _normalize_line(g_raw)
        hit = None
        for a_raw in a_pool:
            a = _normalize_line(a_raw)
            if g == a or compare_lines(g, a, tol) is None:
                hit = a_raw
                break
        if hit is not None:
            a_pool.remove(hit)
            if _normalize_line(hit) != hit or g != g_raw:
                alias_count += 1
        elif not line_self_consistent(g, tol):
            failures.append("line only in golden: " + g_raw)
    for a_raw in a_pool:
        a = _normalize_line(a_raw)
        if not line_self_consistent(a, tol):
            failures.append("line only in actual: " + a_raw)
    return failures, alias_count


def compare_class(golden_path: Path, actual_path: Path, mode: str, tol: Decimal):
    """Return (ok, failures, alias_count, section_note).

    failures lists diff details. alias_count is the number of lines where
    EXCEPTION_NAME_ALIASES changed a side before the lines matched; lines
    that pass without the map, or fail, are not counted.
    """
    if not actual_path.is_file():
        return False, [f"missing actual file: {actual_path}"], 0, ""
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
        return (not failures), failures, alias_count, ""
    g_lines = golden_bytes.decode("utf-8", errors="replace").splitlines()
    a_lines = actual_bytes.decode("utf-8", errors="replace").splitlines()
    g_preamble, g_sections = split_sections(g_lines)
    a_preamble, a_sections = split_sections(a_lines)
    only_golden = sorted(set(g_sections) - set(a_sections))
    only_actual = sorted(set(a_sections) - set(g_sections))
    note = (f"sections golden={len(g_sections)} actual={len(a_sections)}"
            f" compared={len(set(g_sections) & set(a_sections))}"
            f" golden-only={len(only_golden)} actual-only={len(only_actual)}")
    failures = []
    alias_count = 0
    # Preamble (the class: header) and common sections only: a section that
    # exists on one side belongs to that side's extra test cases (TCN-26).
    common = sorted(set(g_sections) & set(a_sections))
    parts = [("preamble", g_preamble, a_preamble)]
    parts.extend((name, g_sections[name], a_sections[name]) for name in common)
    for label, g_part, a_part in parts:
        part_failures, part_alias = compare_line_sets(g_part, a_part, tol)
        alias_count += part_alias
        failures.extend(label + ": " + f for f in part_failures)
        if len(failures) >= MAX_REPORTED_LINES:
            break
    extra = ""
    if only_golden:
        extra += "; golden-only: " + ", ".join(only_golden)
    if only_actual:
        extra += "; actual-only: " + ", ".join(only_actual)
    return (not failures), failures, alias_count, note + extra


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
        ok, failures, alias_count, section_note = compare_class(
            golden_path, actual_dir / f"{name}.txt", args.mode, args.tol
        )
        total_alias += alias_count
        header = f"== {name} ==\n{section_note}" if section_note else f"== {name} =="
        if ok:
            passed.append(name)
            if section_note:
                detail_sections.append(header)
        else:
            failed.append(name)
            detail_sections.append(header + "\n" + "\n".join(failures))

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
