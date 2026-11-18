#!/usr/bin/env python3
"""Hold every npm package to the contract its registry publish depends on.

Three defects reached a release attempt because nothing checked the packed
result before a tag existed: the artifact file name disagreed with the matrix,
the registry name disagreed with the manifest, and a packed manifest carried
workspace: ranges that a consumer cannot resolve. This script owns the three
checks and the one rewrite, so a release lane and the staging pipeline enforce
the same rules.

Usage:
    publish-contract.py --artifacts <dir> [--version V] [--project boring.json]
    publish-contract.py --archive <file.tgz>
    publish-contract.py --package <dir>
    publish-contract.py --resolve <dir> --version V
    publish-contract.py --resolve <dir> --version V --check

--artifacts checks every npm archive in a packed artifact directory against the
matrix: the file the matrix names must exist, its manifest name must be the
registry name the matrix carries, and no dependency field may hold a
workspace: range. --archive applies the manifest checks to one built
npm archive, which is what a release lane hands to npm publish. --package
applies the range check to one package directory before it is packed. --resolve rewrites workspace: ranges to the release
version; --check reports instead of writing, so a lane can refuse a tarball
whose manifest still points at a workspace.

Exit status: 0 the contract holds, 1 it does not, 2 the inputs are unusable.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys
import tarfile

EXIT_OK = 0
EXIT_VIOLATION = 1
EXIT_MISCONFIGURED = 2

DEPENDENCY_FIELDS = (
    "dependencies",
    "devDependencies",
    "peerDependencies",
    "optionalDependencies",
)
WORKSPACE_RANGE = re.compile(r"^workspace:")


class Misconfigured(Exception):
    """An input the script cannot read."""


def read_json(path: pathlib.Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        raise Misconfigured("missing file: %s" % path)
    except json.JSONDecodeError as error:
        raise Misconfigured("%s is not valid JSON: %s" % (path, error))


def stripped_project(path: pathlib.Path) -> dict:
    text = path.read_text(encoding="utf-8")
    return json.loads(re.sub(r"(?m)^[ \t]*//.*$", "", text))


def workspace_ranges(manifest: dict) -> list:
    ranges = []
    for field in DEPENDENCY_FIELDS:
        for name, value in (manifest.get(field) or {}).items():
            if isinstance(value, str) and WORKSPACE_RANGE.match(value):
                ranges.append("%s.%s = %s" % (field, name, value))
    return ranges


def archive_manifest(path: pathlib.Path) -> dict:
    try:
        with tarfile.open(path) as archive:
            member = archive.extractfile("package/package.json")
            if member is None:
                raise Misconfigured("%s carries no package/package.json" % path)
            return json.loads(member.read().decode("utf-8"))
    except tarfile.ReadError as error:
        raise Misconfigured("%s is not a readable archive: %s" % (path, error))


def matrix_npm_entries(project: pathlib.Path, version: str | None) -> list:
    """The npm bundles and the artifact file the matrix expects for each."""
    try:
        import importlib.util

        spec = importlib.util.spec_from_file_location(
            "release_matrix", pathlib.Path(__file__).with_name("release-matrix.py")
        )
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        matrix = module.build_matrix(project, version)
    except Exception as error:  # the matrix module reports its own diagnostics
        raise Misconfigured("the release matrix cannot be built: %s" % error)
    entries = []
    for entry in matrix["bundles"]:
        if entry["ecosystem"] != "npm" or not entry["packed"]:
            continue
        entries.append(
            {
                "id": entry["id"],
                "registryName": entry["registryName"],
                "artifacts": entry["artifacts"],
            }
        )
    return entries


def check_artifacts(directory: pathlib.Path, project: pathlib.Path, version: str | None) -> list:
    if not directory.is_dir():
        raise Misconfigured("missing artifact directory: %s" % directory)
    problems = []
    for entry in matrix_npm_entries(project, version):
        for artifact in entry["artifacts"]:
            path = directory / pathlib.Path(artifact).name
            if not path.is_file():
                problems.append(
                    "bundle %s: the matrix names %s and the pack wrote %s"
                    % (entry["id"], path.name, ", ".join(sorted(p.name for p in directory.iterdir() if p.suffix == ".tgz")) or "no npm archive")
                )
                continue
            manifest = archive_manifest(path)
            if manifest.get("name") != entry["registryName"]:
                problems.append(
                    "bundle %s: %s declares name %r; the matrix publishes %r"
                    % (entry["id"], path.name, manifest.get("name"), entry["registryName"])
                )
            for violation in workspace_ranges(manifest):
                problems.append("bundle %s: %s carries %s" % (entry["id"], path.name, violation))
    for path in sorted(directory.iterdir()):
        if path.suffix != ".tgz":
            continue
        for violation in workspace_ranges(archive_manifest(path)):
            problems.append("archive %s carries %s" % (path.name, violation))
    return problems


def check_archive(path: pathlib.Path) -> list:
    if not path.is_file():
        raise Misconfigured("missing archive: %s" % path)
    manifest = archive_manifest(path)
    problems = []
    if not manifest.get("name"):
        problems.append("%s: the packed manifest declares no name" % path.name)
    if not manifest.get("version"):
        problems.append("%s: the packed manifest declares no version" % path.name)
    for violation in workspace_ranges(manifest):
        problems.append("%s carries %s" % (path.name, violation))
    return problems


def check_package(directory: pathlib.Path) -> list:
    manifest = read_json(directory / "package.json")
    problems = []
    if not manifest.get("name"):
        problems.append("%s: package.json declares no name" % directory)
    if not manifest.get("version"):
        problems.append("%s: package.json declares no version" % directory)
    for violation in workspace_ranges(manifest):
        problems.append("%s: package.json declares %s" % (directory, violation))
    return problems


def resolve_package(directory: pathlib.Path, version: str, write: bool) -> list:
    path = directory / "package.json"
    manifest = read_json(path)
    problems = []
    changed = False
    for field in DEPENDENCY_FIELDS:
        dependencies = manifest.get(field) or {}
        for name, value in list(dependencies.items()):
            if isinstance(value, str) and WORKSPACE_RANGE.match(value):
                if write:
                    dependencies[name] = version
                    changed = True
                else:
                    problems.append("%s: %s.%s still reads %s" % (directory, field, name, value))
    if write and changed:
        path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print("resolved workspace ranges in %s to %s" % (path, version))
    return problems


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description="Check the npm publish contract.")
    parser.add_argument("--artifacts", type=pathlib.Path, default=None)
    parser.add_argument("--archive", type=pathlib.Path, default=None)
    parser.add_argument("--package", type=pathlib.Path, default=None)
    parser.add_argument("--resolve", type=pathlib.Path, default=None)
    parser.add_argument("--project", type=pathlib.Path, default=pathlib.Path("boring.json"))
    parser.add_argument("--version", default=None)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    try:
        if args.artifacts:
            problems = check_artifacts(args.artifacts, args.project, args.version)
        elif args.resolve:
            if not args.version:
                raise Misconfigured("--resolve needs --version")
            problems = resolve_package(args.resolve, args.version, write=not args.check)
        elif args.archive:
            problems = check_archive(args.archive)
        elif args.package:
            problems = check_package(args.package)
        else:
            parser.error("choose --artifacts, --archive, --package or --resolve")
    except Misconfigured as error:
        print("MISCONFIGURED: %s" % error)
        return EXIT_MISCONFIGURED
    if problems:
        for problem in problems:
            print("FAIL: %s" % problem)
        print("publish contract: FAIL (%d)" % len(problems))
        return EXIT_VIOLATION
    print("publish contract: OK")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
