#!/usr/bin/env python3
"""Read boring.json the way every consumer in this repository reads it.

The bundle driver accepts whole-line // comments anywhere: its Config.hx drops
lines whose trimmed text starts with // before it parses. The staging pipeline
reads the same file as strict JSON from the first "{", so a comment line inside
the object body is invisible to the driver and fatal to that reader. A comment
in the leading paragraph is fine for both.

This module states both rules once:

  load_strict       the staging rule: json.loads on the text from the first "{"
  load_driver       the driver rule: drop whole-line // comments, then parse
  body_comments     the comment lines the strict rule cannot carry

Usage (from the repository root):

    python3 tools/project-file.py --out-root [--project boring.json]
    python3 tools/project-file.py --check [--project boring.json]

--check exits 0 when the object body carries no comment, the strict rule parses
it, and both rules yield the same document. It runs its own self-test first, on
a commented sample, so weakening the rule fails this check instead of the
staging lane.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


class ProjectFileError(Exception):
    """The project file cannot be read under the rule being applied."""


def object_text(text: str) -> str:
    """The text the staging pipeline parses: everything from the first brace."""
    index = text.find("{")
    if index < 0:
        raise ProjectFileError("boring.json holds no object: no '{' in the file")
    return text[index:]


def body_comments(text: str, first_line: int = 1) -> list:
    """Whole-line // comments inside the object body, as (line number, text).

    Line numbers are counted from the first line of the file so a message points
    at the line an editor shows. first_line is the file line of the body's first
    line, which the caller derives from the text.
    """
    body = object_text(text)
    offset = text.find("{")
    prefix = text[:offset]
    start = prefix.count("\n") + 1
    found = []
    for number, line in enumerate(body.splitlines(), start=start):
        if line.lstrip().startswith("//"):
            found.append((number, line.strip()))
    return found


def load_strict(text: str) -> dict:
    """The staging rule: strict JSON from the first brace."""
    offset = text.find("{")
    if offset >= 0:
        line_start = text.rfind("\n", 0, offset) + 1
        line_end = text.find("\n", offset)
        head = text[line_start:] if line_end < 0 else text[line_start:line_end]
        if head.lstrip().startswith("//"):
            raise ProjectFileError(
                "the first '{' sits on a comment line, so the staging pipeline starts "
                "parsing inside that comment; keep braces out of the leading paragraph"
            )
    comments = body_comments(text)
    if comments:
        listing = ", ".join(str(number) for number, _ in comments)
        raise ProjectFileError(
            "the object body carries // comments on line(s) %s; the staging pipeline "
            "parses the text from the first '{' as strict JSON, so move them into the "
            "leading paragraph above the object" % listing
        )
    try:
        document = json.loads(object_text(text))
    except json.JSONDecodeError as error:
        raise ProjectFileError("the text from the first '{' is not JSON: %s" % error)
    if not isinstance(document, dict):
        raise ProjectFileError("the text from the first '{' is not a JSON object")
    return document


def load_driver(text: str) -> dict:
    """The driver rule: drop whole-line // comments, then parse."""
    kept = [line for line in text.splitlines() if not line.lstrip().startswith("//")]
    try:
        return json.loads("\n".join(kept))
    except json.JSONDecodeError as error:
        raise ProjectFileError("boring.json is not valid JSON under the driver rule: %s" % error)


def read(project: Path) -> str:
    try:
        return project.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise ProjectFileError("missing project file: %s" % project)


def bundle_ids(document: dict) -> list:
    return [bundle.get("id", "") for bundle in document.get("bundles") or []]


def self_test() -> None:
    """Prove both rules still behave, before they are applied to the real file."""
    commented = "// leading paragraph\n{\n  \"a\": 1,\n  // inline\n  \"b\": 2\n}\n"
    try:
        load_strict(commented)
    except ProjectFileError:
        pass
    else:
        raise ProjectFileError("self-test: the strict rule accepted a body comment")
    if load_driver(commented) != {"a": 1, "b": 2}:
        raise ProjectFileError("self-test: the driver rule dropped more than the comment")
    numbers = [number for number, _ in body_comments(commented)]
    if numbers != [4]:
        raise ProjectFileError("self-test: body_comments reported %r, not [4]" % numbers)

    clean = "// leading paragraph\n{\n  \"a\": 1,\n  \"b\": 2\n}\n"
    if load_strict(clean) != load_driver(clean):
        raise ProjectFileError("self-test: the two rules disagree on a clean file")


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description="Read boring.json under the rules this repository uses.")
    parser.add_argument("--project", type=Path, default=Path("boring.json"))
    parser.add_argument("--out-root", action="store_true", help="print the project outRoot and exit")
    parser.add_argument("--check", action="store_true", help="fail when the object body carries a comment")
    args = parser.parse_args(argv)

    if args.out_root == args.check:
        parser.error("choose one of --out-root and --check")

    try:
        text = read(args.project)
        if args.out_root:
            print(load_strict(text)["outRoot"])
            return 0
        self_test()
        strict = load_strict(text)
        driver = load_driver(text)
        if strict != driver:
            raise ProjectFileError(
                "the strict rule and the driver rule parse to different documents; "
                "a comment is changing the meaning of the file"
            )
    except ProjectFileError as error:
        print("project-file: %s" % error)
        return 1

    print(
        "project-file: %s is strict JSON after the first brace; %d bundles; outRoot=%s"
        % (args.project, len(bundle_ids(strict)), strict.get("outRoot"))
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

