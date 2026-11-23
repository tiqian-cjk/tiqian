#!/usr/bin/env python3
"""Embed the source repository URL in packed npm manifests.

npm validates the provenance bundle against the package manifest: a manifest
without "repository.url" is refused with 422 before anything is stored. The
generated manifests from the bundler do not carry the field, so this rewrites
the archive in place after packing and before the artifacts are recorded.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import sys
import tarfile
from pathlib import Path

REPOSITORY_URL = "https://github.com/tiqian-cjk/tiqian.git"


def rewrite(archive: Path, url: str) -> bool:
    with tarfile.open(archive, "r:gz") as handle:
        members = handle.getmembers()
        contents = {member.name: handle.extractfile(member).read() for member in members if member.isfile()}

    manifest_name = "package/package.json"
    if manifest_name not in contents:
        return False
    manifest = json.loads(contents[manifest_name].decode("utf-8"))
    if isinstance(manifest.get("repository"), dict) and manifest["repository"].get("url"):
        return False

    manifest["repository"] = {"type": "git", "url": url}
    contents[manifest_name] = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")

    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w:gz") as handle:
        for member in members:
            info = tarfile.TarInfo(member.name)
            info.mode = member.mode
            info.uid = member.uid
            info.gid = member.gid
            info.uname = member.uname
            info.gname = member.gname
            info.mtime = member.mtime
            info.type = member.type
            if member.isfile():
                data = contents[member.name]
                info.size = len(data)
                handle.addfile(info, io.BytesIO(data))
            else:
                handle.addfile(info)
    archive.write_bytes(buffer.getvalue())
    return True


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Embed the repository URL in packed npm manifests.")
    parser.add_argument("archives", nargs="+", type=Path)
    parser.add_argument("--url", default=REPOSITORY_URL)
    parser.add_argument(
        "--tree",
        type=Path,
        help="registry tree written by the pack run; its npm sha512 values are refreshed",
    )
    args = parser.parse_args(argv)

    changed = 0
    for archive in args.archives:
        if rewrite(archive, args.url):
            changed += 1
            print(f"embedded repository in {archive.name}")
            if args.tree is not None:
                update_tree_digest(archive, args.tree)
        else:
            print(f"left {archive.name} unchanged")
    print(f"embedded repository in {changed} archive(s)")
    return 0


def update_tree_digest(archive: Path, tree: Path) -> None:
    """Keep the registry metadata in step with the rewritten archive."""
    with tarfile.open(archive, "r:gz") as handle:
        manifest = json.loads(handle.extractfile("package/package.json").read().decode("utf-8"))
    digest = base64.b64encode(hashlib.sha512(archive.read_bytes()).digest()).decode("ascii")
    name = manifest["name"]
    version = manifest["version"]
    encoded = name.replace("/", "%2f")
    for metadata in tree.rglob(f"@*%2f*/{version}/npm/metadata.json"):
        record = json.loads(metadata.read_text())
        if record.get("name") != name:
            continue
        record["sha512"] = digest
        metadata.write_text(json.dumps(record, indent=2) + "\n")
        print(f"updated {metadata.relative_to(tree)}")



if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
