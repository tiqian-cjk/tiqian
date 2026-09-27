#!/usr/bin/env python3
"""Compare named test sections of a produced trace against golden sections.

A batch lane translates a subset of a test class's tests, so the whole-class
compare of compare-traces.py fails on the missing sections alone. This tool
extracts each named `test:` section from both files (a section runs from its
`test:` line until the next `test:` or `class:` line) and compares only those
sections with the same tolerance pipeline as compare-traces.py tolerance
mode. Line order inside the section and section order across the file do not
matter; a section is found by name on each side independently.

Usage:
  section-check.py [--tol 1e-6] golden.txt actual.txt <test-name> [<test-name> ...]

Exit 0 iff every named section is present on both sides and identical under
the comparison rules. Each name prints one PASS or FAIL line; FAIL lines
carry up to 8 diff details.
"""

import argparse
import importlib.util
import sys
from decimal import Decimal
from pathlib import Path

# compare-traces.py has a hyphen in its name, so it is not importable as a
# module; load it from the same directory by path.
_spec = importlib.util.spec_from_file_location(
    "compare_traces", Path(__file__).resolve().parent / "compare-traces.py"
)
compare_traces = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(compare_traces)


def split_sections(path: Path):
    """Return {test name: [section lines]} for one trace file."""
    sections = {}
    current_name = None
    current_lines = []
    for line in path.read_bytes().decode("utf-8", errors="replace").splitlines():
        if line.startswith("test: "):
            if current_name is not None:
                sections[current_name] = current_lines
            current_name = line[len("test: "):]
            current_lines = [line]
        elif line.startswith("class: "):
            if current_name is not None:
                sections[current_name] = current_lines
            current_name = None
            current_lines = []
        elif current_name is not None:
            current_lines.append(line)
    if current_name is not None:
        sections[current_name] = current_lines
    return sections


def compare_section(golden_lines, actual_lines, tol):
    """Return a list of failure strings; empty means the section matches."""
    failures = []
    if len(golden_lines) != len(actual_lines):
        return [
            f"line count {len(golden_lines)} vs {len(actual_lines)}"
        ]
    for i, (g_raw, a_raw) in enumerate(zip(golden_lines, actual_lines)):
        g = compare_traces.normalize_truncation_stamps(
            compare_traces.normalize_collection_joins(
                compare_traces.normalize_exception_names(g_raw)
            )
        )
        a = compare_traces.normalize_truncation_stamps(
            compare_traces.normalize_collection_joins(
                compare_traces.normalize_exception_names(a_raw)
            )
        )
        reason = compare_traces.compare_lines(g, a, tol)
        if reason is not None:
            failures.append(f"line {i + 1}: {reason}")
            if len(failures) >= 8:
                break
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("golden", type=Path)
    parser.add_argument("actual", type=Path)
    parser.add_argument("names", nargs="+", help="test names to compare")
    parser.add_argument("--tol", type=Decimal, default=Decimal("1e-6"))
    args = parser.parse_args()

    if not args.actual.is_file():
        print(f"missing actual file: {args.actual}")
        return 1
    golden_sections = split_sections(args.golden)
    actual_sections = split_sections(args.actual)

    failed = 0
    for name in args.names:
        if name not in golden_sections:
            print(f"FAIL {name}: no golden section")
            failed += 1
            continue
        if name not in actual_sections:
            print(f"FAIL {name}: no actual section")
            failed += 1
            continue
        failures = compare_section(
            golden_sections[name], actual_sections[name], args.tol
        )
        if failures:
            print(f"FAIL {name}")
            for f in failures:
                print(f"  {f}")
            failed += 1
        else:
            print(f"PASS {name}")
    print(f"sections: {len(args.names)} pass={len(args.names) - failed} fail={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
