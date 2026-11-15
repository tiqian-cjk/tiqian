#!/usr/bin/env python3
"""Merge one pack run's registry tree into the registry repository.

The registry repository holds published versions: a release adds its version
directories under <owner>/<package>/ and leaves every earlier version in
place, so a consumer pinned to an older version still resolves. The registry
tool reads the whole tree and lists every version it finds, so the site shows
the history and the newest release together.

Usage:
    merge-registry-tree.py --tree <registry-tree> --owner <owner> --registry <clone> [--retire <version>]...
    merge-registry-tree.py --selftest

For every repository directory under <tree>/<owner> the merge copies the
repository level files (README.md) over the clone and replaces
<clone>/<owner>/<repo>/<version> in full for every version directory the run
names. Version directories the run does not name, and repositories it does
not name, stay untouched. Re-running the same release writes the same bytes,
so the commit stays empty.

Versions named with --retire are deleted from every repository under the
owner after the merge; a repository left without any version directory is
removed as a whole, because the registry tool refuses a repository with no
versions. Retirement is idempotent: a version that is already absent is not
an error.

Exit status: 0 merged, 1 a malformed tree, 2 a misconfigured invocation.
"""
from __future__ import annotations

import argparse
import hashlib
import shutil
import sys
import tempfile
from pathlib import Path

EXIT_OK = 0
EXIT_TREE = 1
EXIT_MISCONFIGURED = 2


def fail(message: str) -> None:
    raise SystemExit("FAIL: " + message)


def reject_symlinks(path: Path) -> None:
    """Refuse symbolic links and special files; the pack tree holds neither."""
    if path.is_symlink():
        fail("%s is a symbolic link; the registry tree holds regular files and directories only" % path)
    if path.is_file() or path.is_dir():
        return
    fail("%s is neither a regular file nor a directory" % path)


def check_tree(path: Path) -> None:
    reject_symlinks(path)
    if path.is_dir():
        for child in sorted(path.iterdir()):
            check_tree(child)


def copy_file(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def replace_directory(source: Path, target: Path) -> None:
    if target.is_symlink() or target.is_file():
        target.unlink()
    elif target.is_dir():
        shutil.rmtree(target)
    shutil.copytree(source, target)


def merge_repository(source: Path, target: Path) -> int:
    versions = 0
    target.mkdir(parents=True, exist_ok=True)
    for entry in sorted(source.iterdir()):
        if entry.is_dir():
            replace_directory(entry, target / entry.name)
            versions += 1
        else:
            copy_file(entry, target / entry.name)
    return versions


def merge(tree: Path, owner: str, registry: Path) -> int:
    source_owner = tree / owner
    if not source_owner.is_dir():
        fail("%s is missing; the pack run wrote no registry tree" % source_owner)
    check_tree(source_owner)
    target_owner = registry / owner
    versions = 0
    for entry in sorted(source_owner.iterdir()):
        if not entry.is_dir():
            fail("%s is a stray file at the owner level" % entry)
        versions += merge_repository(entry, target_owner / entry.name)
    if versions == 0:
        fail("%s holds no version directory" % source_owner)
    print("merged %d version directories from %s into %s" % (versions, source_owner, target_owner))
    return versions


def validate_version(version: str) -> None:
    if not version or version in (".", "..") or "/" in version:
        fail("--retire takes a plain version name, got %r" % version)


def retire(registry: Path, owner: str, versions: list) -> int:
    """Delete the named version directories from every repository under owner."""
    target_owner = registry / owner
    if not target_owner.is_dir():
        return 0
    removed = 0
    for repo in sorted(target_owner.iterdir()):
        if not repo.is_dir():
            continue
        for version in versions:
            victim = repo / version
            if victim.is_symlink() or victim.is_file():
                victim.unlink()
                removed += 1
            elif victim.is_dir():
                shutil.rmtree(victim)
                removed += 1
        if not any(entry.is_dir() for entry in repo.iterdir()):
            shutil.rmtree(repo)
    return removed


def snapshot(root: Path) -> dict:
    out = {}
    for path in sorted(root.rglob("*")):
        if path.is_file():
            out[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return out


def version_names(root: Path) -> list:
    if not root.is_dir():
        return []
    return sorted(entry.name for entry in root.iterdir() if entry.is_dir())


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def metadata(repo: str, version: str) -> str:
    return '{"name": "%s", "version": "%s"}\n' % (repo, version)


def stage(root: Path, owner: str, repo: str, version: str, platforms: list, readme: str) -> None:
    write(root / owner / repo / "README.md", readme)
    for platform in platforms:
        write(root / owner / repo / version / platform / "metadata.json", metadata(repo, version))


def selftest() -> int:
    owner, repo = "tiqian-cjk", "tiqian-engine"
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        clone = root / "clone"
        write(clone / owner / repo / "0.0.9-old" / "npm" / "metadata.json", metadata(repo, "0.0.9-old"))

        first = root / "first"
        stage(first, owner, repo, "0.1.0", ["npm"], "engine first\n")
        merge(first, owner, clone)
        assert version_names(clone / owner / repo) == ["0.0.9-old", "0.1.0"], "the first release must add its version and keep the earlier one"
        assert (clone / owner / repo / "README.md").read_text(encoding="utf-8") == "engine first\n"

        second = root / "second"
        stage(second, owner, repo, "0.2.0", ["npm"], "engine second\n")
        merge(second, owner, clone)
        assert version_names(clone / owner / repo) == ["0.0.9-old", "0.1.0", "0.2.0"], "the second release must keep every earlier version"

        wider = root / "wider"
        stage(wider, owner, repo, "0.2.0", ["npm", "cargo"], "engine second\n")
        merge(wider, owner, clone)
        assert version_names(clone / owner / repo / "0.2.0") == ["cargo", "npm"], "republishing a version must write every platform of that run"

        narrower = root / "narrower"
        stage(narrower, owner, repo, "0.2.0", ["npm"], "engine third\n")
        merge(narrower, owner, clone)
        assert version_names(clone / owner / repo) == ["0.0.9-old", "0.1.0", "0.2.0"], "republishing a version must not add a second directory"
        assert version_names(clone / owner / repo / "0.2.0") == ["npm"], "republishing a version must replace the directory instead of accumulating"
        assert (clone / owner / repo / "README.md").read_text(encoding="utf-8") == "engine third\n"

        before = snapshot(clone)
        merge(narrower, owner, clone)
        assert snapshot(clone) == before, "merging the same release twice must leave the tree unchanged"

        retired = root / "retired"
        stage(retired, owner, "old-only", "0.0.1-old", ["npm"], "old\n")
        merge(retired, owner, clone)
        assert version_names(clone / owner / "old-only") == ["0.0.1-old"], "the single-version sample must be present before retirement"
        removed = retire(clone, owner, ["0.0.9-old", "0.0.1-old"])
        assert removed == 2, "retirement must count every removed version directory"
        assert version_names(clone / owner / repo) == ["0.1.0", "0.2.0"], "a retired version must be gone from the surviving repository"
        assert not (clone / owner / "old-only").exists(), "a repository left with no version directory must be removed"
        assert retire(clone, owner, ["0.0.9-old"]) == 0, "retiring an absent version must be a no-op"
        print("selftest: OK (v1 and v2 both present, repeated v2 writes one directory, retirement removes named versions and empty repositories)")
    return EXIT_OK


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description="Merge a pack registry tree into the registry repository.")
    parser.add_argument("--selftest", action="store_true", help="run the two-version sample tree check")
    parser.add_argument("--tree", type=Path)
    parser.add_argument("--owner")
    parser.add_argument("--registry", type=Path)
    parser.add_argument("--retire", action="append", default=[], metavar="VERSION",
                        help="delete this version directory from every repository under --owner")
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    if not args.tree or not args.owner or not args.registry:
        parser.error("--tree, --owner and --registry are required unless --selftest is given")
    if not args.registry.is_dir():
        print("MISCONFIGURED: registry clone is missing: %s" % args.registry)
        return EXIT_MISCONFIGURED
    for version in args.retire:
        validate_version(version)
    merge(args.tree, args.owner, args.registry)
    if args.retire:
        removed = retire(args.registry, args.owner, args.retire)
        print("retired %d version directories from %s: %s" % (removed, args.owner, ", ".join(args.retire)))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
