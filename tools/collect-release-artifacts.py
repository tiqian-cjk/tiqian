#!/usr/bin/env python3
"""Copy the files one pack run named in its registry tree into a flat artifact directory.

release-registry.yml checks the release artifacts against the registry tree the
same pack run wrote: every file a metadata.json names must be present in
release-artifacts with the digest SHA256SUMS records, and every artifact must be
named by the tree. Collecting with an extension allowlist cannot satisfy that
check once the pack run starts writing a new artifact type, because the allowlist
names the types that existed when it was written. The Kotlin Multiplatform
publication added the Gradle Module Metadata (`.module`), the Kotlin/Native
payload (`.klib`) and the Android archive (`.aar`) to the Maven metadata while
the allowlist stayed behind. This tool reads the file names out of the tree
instead, and it derives them with the same function tools/check-registry-tree.py
uses, so the collect step and the check step cannot disagree about which files a
pack run produced.

Usage:
    collect-release-artifacts.py --tree <registry-tree> --source <out-root> --artifacts <release-artifacts>

The source root is the outRoot of boring.json (engine-haxe/out). A referenced
file is located by its base name under that root. Two files with the same base
name are accepted only when their bytes are identical, because the release
artifact directory is flat and one name has to mean one file there.

Exit status: 0 every referenced file was copied, 1 a referenced file is missing
or two different files share its name, 2 a misconfigured invocation.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import pathlib
import shutil
import sys

EXIT_OK = 0
EXIT_MISMATCH = 1
EXIT_MISCONFIGURED = 2


def load_check_module():
    """The check module that owns the metadata-to-file-name mapping.

    check-registry-tree.py is a script rather than an importable module: its
    name carries a hyphen, so it is loaded by path. Loading it defines names
    only; it does nothing until main is called under __main__.
    """
    path = pathlib.Path(__file__).resolve().parent / "check-registry-tree.py"
    spec = importlib.util.spec_from_file_location("check_registry_tree", path)
    if spec is None or spec.loader is None:
        print("MISCONFIGURED: cannot load the metadata mapping from %s" % path)
        return None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def metadata_entries(tree: pathlib.Path, check) -> tuple:
    """Every (metadata path, platform, version, repo dir, metadata) under the tree.

    The layout is the one check-registry-tree.py reads:
    <tree>/<owner>/<package>/<version>/<platform>/metadata.json. A file whose
    platform the check does not know is reported and skipped, as the check does.
    """
    entries = []
    failures = []
    for path in sorted(tree.rglob("metadata.json")):
        platform_dir = path.parent
        version_dir = platform_dir.parent
        repo_dir = version_dir.parent
        platform = platform_dir.name
        version = version_dir.name
        if platform not in check.DIGEST_FIELD and platform != "maven":
            failures.append("%s: unknown platform %s" % (path, platform))
            continue
        try:
            metadata = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            failures.append("%s is not valid JSON: %s" % (path, error))
            continue
        entries.append((path, platform, version, repo_dir.name, metadata))
    return entries, failures


def locate_all(wanted: set, source: pathlib.Path) -> dict:
    """Every file under the source root whose base name is one of wanted."""
    found = {}
    for path in source.rglob("*"):
        if path.name in wanted and path.is_file():
            found.setdefault(path.name, []).append(path)
    return found


def digest_of(path: pathlib.Path) -> str:
    handle = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1 << 20), b""):
            handle.update(block)
    return handle.hexdigest()


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description="Collect the artifacts one registry tree names.")
    parser.add_argument("--tree", type=pathlib.Path, required=True)
    parser.add_argument("--source", type=pathlib.Path, required=True)
    parser.add_argument("--artifacts", type=pathlib.Path, required=True)
    args = parser.parse_args(argv)
    if not args.tree.is_dir():
        print("MISCONFIGURED: registry tree is missing: %s" % args.tree)
        return EXIT_MISCONFIGURED
    if not args.source.is_dir():
        print("MISCONFIGURED: pack output root is missing: %s" % args.source)
        return EXIT_MISCONFIGURED

    check = load_check_module()
    if check is None:
        return EXIT_MISCONFIGURED

    entries, failures = metadata_entries(args.tree, check)
    if not entries:
        print("FAIL: the tree names no metadata.json")
        return EXIT_MISMATCH

    referenced = []
    for path, platform, version, repo_dir, metadata in entries:
        for name in check.referenced(metadata, platform, repo_dir, version):
            referenced.append((path, name))

    wanted = {name for _, name in referenced if name}
    if not wanted:
        print("FAIL: the tree names no artifact file")
        return EXIT_MISMATCH

    found = locate_all(wanted, args.source)
    args.artifacts.mkdir(parents=True, exist_ok=True)
    copied = []
    for path, name in referenced:
        if not name:
            failures.append("%s: a referenced artifact has no file name" % path)
            continue
        if name in copied:
            continue
        candidates = found.get(name, [])
        if not candidates:
            failures.append("%s: %s is not under %s" % (path, name, args.source))
            continue
        if len(candidates) > 1 and len({digest_of(candidate) for candidate in candidates}) > 1:
            failures.append("%s: %s names %d different files under %s: %s"
                            % (path, name, len(candidates), args.source,
                               ", ".join(str(candidate) for candidate in candidates)))
            continue
        shutil.copyfile(candidates[0], args.artifacts / name)
        copied.append(name)
        print("collected %s <- %s" % (name, candidates[0]))

    if failures:
        for failure in failures:
            print("FAIL: %s" % failure)
        print("collect: FAIL (%d)" % len(failures))
        return EXIT_MISMATCH
    print("collect: OK (%d metadata entries, %d artifacts)" % (len(entries), len(copied)))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
