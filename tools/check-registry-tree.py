#!/usr/bin/env python3
"""Check the registry metadata tree against the artifacts of one pack run.

The release-registry job downloads two artifacts from the pack job:
release-artifacts (the install units plus SHA256SUMS) and registry-tree (the
metadata the same pack run wrote). This script requires every file the tree
names to be present in release-artifacts with the sha256 the pack job recorded
in SHA256SUMS and, where the platform records a digest, with the digest the
metadata states. Every artifact must also be named at least once, so a
metadata entry without an artifact or an artifact the tree never names
fails.

Usage:
    check-registry-tree.py --tree <registry-tree> --artifacts <release-artifacts>

Exit status: 0 the tree and the artifacts agree, 1 a disagreement, 2 a
misconfigured invocation.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import pathlib
import sys

EXIT_OK = 0
EXIT_MISMATCH = 1
EXIT_MISCONFIGURED = 2

# The digest field each platform records in metadata.json, and its encoding.
# packages/registry/src/registry/Core.hx reads these field names: npm carries
# a base64 sha512, cargo, pub and swift carry a hex sha256, and maven carries
# one entry per file without a digest, so maven relies on SHA256SUMS.
DIGEST_FIELD = {"npm": "sha512", "cargo": "sha256", "pub": "sha256", "swift": "sha256"}
DIGEST_ENCODING = {"npm": "base64", "cargo": "hex", "pub": "hex", "swift": "hex"}


def digest_of(path: pathlib.Path, field: str, encoding: str) -> str:
    handle = hashlib.new("sha512" if field == "sha512" else "sha256")
    handle.update(path.read_bytes())
    if encoding == "base64":
        return base64.b64encode(handle.digest()).decode("ascii")
    return handle.hexdigest()


def artifact_files(directory: pathlib.Path) -> dict:
    if not directory.is_dir():
        raise SystemExit("MISCONFIGURED: artifacts directory is missing: %s" % directory)
    return {
        entry.name: entry
        for entry in sorted(directory.iterdir())
        if entry.is_file() and entry.name != "SHA256SUMS"
    }


def read_sums(directory: pathlib.Path) -> dict:
    path = directory / "SHA256SUMS"
    if not path.is_file():
        return {}
    sums = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        digest, _, name = line.partition("  ")
        if name.strip():
            sums[name.strip()] = digest.strip().lower()
    return sums


def referenced(metadata: dict, platform: str, repo_dir: str, version: str) -> list:
    if platform == "maven":
        return [item.get("file", "") for item in metadata.get("artifacts", [])]
    if platform == "swift":
        # The archive key is swift/<scope>/<name>/<version>.zip and the packed
        # file is <name>-<version>.zip beside the output tree.
        return ["%s-%s.zip" % (repo_dir, version)]
    url = metadata.get("url", "")
    return [url.rsplit("/", 1)[-1]]


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description="Check registry metadata against the pack artifacts.")
    parser.add_argument("--tree", type=pathlib.Path, required=True)
    parser.add_argument("--artifacts", type=pathlib.Path, required=True)
    args = parser.parse_args(argv)
    if not args.tree.is_dir():
        print("MISCONFIGURED: tree directory is missing: %s" % args.tree)
        return EXIT_MISCONFIGURED
    artifacts = artifact_files(args.artifacts)
    sums = read_sums(args.artifacts)
    referenced_names = set()
    failures = []
    if not sums:
        failures.append("release-artifacts/SHA256SUMS is missing or empty; the pack job records the artifact digests")
    entries = sorted(args.tree.rglob("metadata.json"))
    if not entries:
        failures.append("the tree names no metadata.json")
    for path in entries:
        platform_dir = path.parent
        version_dir = platform_dir.parent
        repo_dir = version_dir.parent
        platform = platform_dir.name
        version = version_dir.name
        if platform not in DIGEST_FIELD and platform != "maven":
            failures.append("%s: unknown platform %s" % (path, platform))
            continue
        try:
            metadata = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            failures.append("%s is not valid JSON: %s" % (path, error))
            continue
        names = referenced(metadata, platform, repo_dir.name, version)
        for name in names:
            if not name:
                failures.append("%s: a referenced artifact has no file name" % path)
                continue
            referenced_names.add(name)
            target = artifacts.get(name)
            if target is None:
                failures.append("%s: %s is not in release-artifacts" % (path, name))
                continue
            recorded_sum = sums.get(name)
            if recorded_sum is None:
                failures.append("%s: %s is not recorded in SHA256SUMS" % (path, name))
            else:
                actual_sum = hashlib.sha256(target.read_bytes()).hexdigest()
                if actual_sum != recorded_sum:
                    failures.append("%s: %s sha256 %s does not match SHA256SUMS %s" % (path, name, actual_sum, recorded_sum))
            field = DIGEST_FIELD.get(platform)
            if field is None:
                continue
            recorded = metadata.get(field)
            if not recorded:
                failures.append("%s: %s records no %s" % (path, name, field))
                continue
            actual = digest_of(target, field, DIGEST_ENCODING[platform])
            if actual.lower() != recorded.strip().lower():
                failures.append("%s: %s digest %s does not match %s" % (path, name, actual, recorded.strip()))
        print("checked %s: %s" % (platform, ", ".join(names)))
    for name in sorted(set(artifacts) - referenced_names):
        failures.append("%s is not named by any metadata.json" % name)
    if failures:
        for failure in failures:
            print("FAIL: %s" % failure)
        print("check: FAIL (%d)" % len(failures))
        return EXIT_MISMATCH
    print("check: OK (%d metadata entries, %d artifacts)" % (len(entries), len(artifacts)))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
