#!/usr/bin/env python3
"""Prepare packages from a successful Neon run for publication."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile


def checked_archive(
    source: Path, package: str, version: str, content: str,
) -> Path:
    stem = package.removeprefix("@").replace("/", "-")
    matches = list(source.rglob(f"{stem}-{version}.tgz"))
    if len(matches) != 1:
        raise ValueError(f"expected one archive for {package}@{version}, found {len(matches)}")

    with tarfile.open(matches[0], "r:gz") as archive:
        manifest = json.load(archive.extractfile("package/package.json"))
        if (manifest["name"], manifest["version"]) != (package, version):
            raise ValueError(f"{matches[0].name} declares a different package or version")
        artifact = archive.getmember(f"package/{content}")
        if not artifact.isfile() or artifact.size == 0:
            raise ValueError(f"{matches[0].name} has no usable {content}")
    return matches[0]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="downloaded Neon package set")
    parser.add_argument("output", type=Path)
    parser.add_argument("version")
    args = parser.parse_args()

    # Require the whole package set for the exact release version.
    source_manifest = Path("platforms/web/server/core/package.json")
    manifest = json.loads(source_manifest.read_text(encoding="utf-8"))
    if manifest["version"] != args.version:
        parser.error("the checked-out precompute manifest has a different version")
    native = {
        platform: checked_archive(args.source, f"@tiqian/precompute-{platform}", args.version, "index.node")
        for platform in manifest["neon"]["platforms"]
    }
    main_archive = checked_archive(args.source, manifest["name"], args.version, "lib/fonts.js")

    # Repack the already-built JS after resolving workspace ranges for npm.
    package_dir = args.output.resolve() / "main-package"
    package_dir.mkdir(parents=True, exist_ok=True)
    contract = Path(__file__).with_name("publish-contract.py").resolve()
    npm = shutil.which("npm.cmd" if os.name == "nt" else "npm")
    with tempfile.TemporaryDirectory() as temporary:
        with tarfile.open(main_archive, "r:gz") as archive:
            archive.extractall(temporary, filter="data")
        source = Path(temporary) / "package"
        subprocess.run([sys.executable, contract, "--resolve", source, "--version", args.version], check=True)
        subprocess.run([npm, "pack", "--ignore-scripts", "--pack-destination", package_dir], cwd=source, check=True)
    packed = checked_archive(package_dir, manifest["name"], args.version, "lib/fonts.js")
    subprocess.run([sys.executable, contract, "--archive", packed], check=True)

    # Copy the platform packages byte for byte after checking their manifests.
    for platform, archive in native.items():
        subprocess.run([sys.executable, contract, "--archive", archive], check=True)
        destination = args.output / f"binary-package-{platform}"
        destination.mkdir(parents=True, exist_ok=True)
        shutil.copy2(archive, destination)


if __name__ == "__main__":
    main()
