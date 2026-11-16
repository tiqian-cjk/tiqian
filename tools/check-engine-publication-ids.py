#!/usr/bin/env python3
"""Assert every :platforms:engine publication artifactId carries the tiqian-engine prefix.

The root build script rewrites each MavenPublication artifactId, and the poms
are only written during a publish, so no ordinary compile covers this. The
check reads the publications through tools/check-engine-publication-ids.init.gradle,
which registers a task and reads in doLast: an init-script gradle.projectsEvaluated
callback runs before the build script's own callback and would observe the
pre-rewrite value.

Usage:
    check-engine-publication-ids.py [--offline] [--gradle-arg ARG ...]

Exit status: 0 every :platforms:engine publication is prefixed, 1 a publication
is missing or not prefixed, 2 the checker or the gradle run is unusable.
"""
from __future__ import annotations

import argparse
import pathlib
import subprocess
import sys

EXIT_OK = 0
EXIT_MISMATCH = 1
EXIT_MISCONFIGURED = 2

PREFIX = "tiqian-engine"
EXPECTED_COUNT = 9
MARKER = "ARTIFACT_ID|"


def run_gradle(repo: pathlib.Path, init_script: pathlib.Path, extra: list) -> str:
    wrapper = repo / "gradlew"
    if not wrapper.is_file():
        raise SystemExit("MISCONFIGURED: gradle wrapper is missing: %s" % wrapper)
    command = [str(wrapper), "-I", str(init_script), ":platforms:engine:printArtifactIds"]
    command.extend(extra)
    completed = subprocess.run(command, cwd=repo, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return completed.stdout


def parse(output: str) -> dict:
    publications = {}
    for line in output.splitlines():
        if not line.startswith(MARKER):
            continue
        fields = line.split("|")
        if len(fields) < 4:
            continue
        publications[fields[2]] = fields[3]
    return publications


def main(argv: list, repo: pathlib.Path) -> int:
    parser = argparse.ArgumentParser(description="Check the :platforms:engine publication artifact ids.")
    parser.add_argument("--offline", action="store_true", help="pass --offline to gradle")
    parser.add_argument("--gradle-arg", action="append", default=[], help="extra gradle argument (repeatable)")
    args = parser.parse_args(argv)
    extra = list(args.gradle_arg)
    if args.offline:
        extra.append("--offline")
    init_script = repo / "tools" / "check-engine-publication-ids.init.gradle"
    if not init_script.is_file():
        print("MISCONFIGURED: init script is missing: %s" % init_script)
        return EXIT_MISCONFIGURED
    output = run_gradle(repo, init_script, extra)
    publications = parse(output)
    if not publications:
        print("MISCONFIGURED: the gradle run printed no publication; output tail follows")
        for line in output.splitlines()[-40:]:
            print("  " + line)
        return EXIT_MISCONFIGURED
    failures = []
    for name in sorted(publications):
        artifact_id = publications[name]
        status = "ok" if artifact_id.startswith(PREFIX) else "not prefixed"
        print("%-20s %-30s %s" % (name, artifact_id, status))
        if not artifact_id.startswith(PREFIX):
            failures.append("%s: artifactId %r does not start with %r" % (name, artifact_id, PREFIX))
    if len(publications) != EXPECTED_COUNT:
        failures.append("expected %d :platforms:engine publications, found %d" % (EXPECTED_COUNT, len(publications)))
    if failures:
        for failure in failures:
            print("FAIL: %s" % failure)
        print("check: FAIL (%d)" % len(failures))
        return EXIT_MISMATCH
    print("check: OK (%d :platforms:engine publications, all prefixed with %s)" % (len(publications), PREFIX))
    return EXIT_OK


if __name__ == "__main__":
    ROOT = pathlib.Path(__file__).resolve().parents[1]
    sys.exit(main(sys.argv[1:], ROOT))
