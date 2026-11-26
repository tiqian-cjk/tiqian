#!/usr/bin/env python3
"""Rewrite the package name and version inside a packed npm tarball.

The generated engine, protocol and shared trees are packed by `boring pack`
with their repository names (@tiqian/<name>) and the placeholder version. A
snapshot publishes them under the fork scope and the snapshot version, so this
script rewrites `package/package.json` inside the tarball and writes the result
beside it.

Usage:
    rewrite-npm-tarball.py --scope @owner --version 0.1.0-alpha.9-abc123 \
        --output-dir <dir> <tarball>
"""
import argparse
import io
import json
import pathlib
import tarfile


def rewrite_manifest(manifest, scope, version):
    name = manifest.get("name", "")
    if name.startswith("@tiqian/"):
        manifest["name"] = scope + "/" + name.split("/", 1)[1]
    manifest["version"] = version
    for field in ("dependencies", "devDependencies", "peerDependencies", "optionalDependencies"):
        dependencies = manifest.get(field)
        if not dependencies:
            continue
        rewritten = {}
        for key, value in dependencies.items():
            if key.startswith("@tiqian/"):
                rewritten[scope + "/" + key.split("/", 1)[1]] = version
            else:
                rewritten[key] = value
        manifest[field] = rewritten
    return manifest


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scope", required=True, help="npm scope of the snapshot, e.g. @owner")
    parser.add_argument("--version", required=True, help="snapshot version")
    parser.add_argument("--output-dir", required=True, help="directory to write the rewritten tarball")
    parser.add_argument("tarball", help="tarball produced by boring pack")
    args = parser.parse_args()

    source = pathlib.Path(args.tarball)
    output_directory = pathlib.Path(args.output_dir)
    output_directory.mkdir(parents=True, exist_ok=True)

    with tarfile.open(source, "r:gz") as archive:
        members = archive.getmembers()
        manifest_member = next(
            member for member in members if member.name == "package/package.json"
        )
        manifest = json.loads(archive.extractfile(manifest_member).read().decode("utf-8"))
        manifest = rewrite_manifest(manifest, args.scope, args.version)
        output = output_directory / (
            manifest["name"].replace("@", "").replace("/", "-")
            + "-"
            + args.version
            + ".tgz"
        )
        with tarfile.open(output, "w:gz") as rewritten:
            for member in members:
                if member.isfile():
                    data = archive.extractfile(member).read()
                    if member.name == "package/package.json":
                        data = (json.dumps(manifest, indent=2) + "\n").encode("utf-8")
                        member.size = len(data)
                    rewritten.addfile(member, io.BytesIO(data))
                else:
                    rewritten.addfile(member)
    print(output)


if __name__ == "__main__":
    main()
