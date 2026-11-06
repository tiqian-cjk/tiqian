#!/usr/bin/env python3
"""Write the registry metadata tree for one release.

The registry tool accepts exactly one metadata.json per version and platform
(packages/registry/src/registry/Core.hx:280), so every package owns its own
repository layer and the tree path is <owner>/<package>/<version>/<platform>/.

Usage:
  registry-metadata.py --project boring.json --artifacts release-artifacts \
      --version 0.1.0-alpha06 --owner tiqian-cjk --repo tiqian \
      --asset-base https://github.com/tiqian-cjk/tiqian/releases/download/v0.1.0-alpha06 --out tree
"""
import argparse
import hashlib
import json
import pathlib
import re
import sys

TARGET_PLATFORM = {"rust": "cargo", "ts": "npm", "kotlin": "maven", "swift": "swift", "dart": "pub"}
PLATFORM_DIGEST = {"cargo": "sha256", "pub": "sha256", "swift": "sha256", "npm": "sha512", "maven": "sha1"}
PLATFORM_SUFFIX = {"cargo": ".crate", "pub": ".tar.gz", "swift": ".zip", "npm": ".tgz", "maven": ".jar"}


def load_bundles(path):
    text = pathlib.Path(path).read_text()
    text = re.sub(r"^\s*//.*$", "", text, flags=re.M)
    return json.loads(text)["bundles"]


def digest_of(path, algo):
    h = hashlib.new(algo)
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--artifacts", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--asset-base", required=True,
                        help="where the published archives are downloaded from; the release asset URL")
    parser.add_argument("--out", required=True)
    options = parser.parse_args()

    artifacts = pathlib.Path(options.artifacts)
    out = pathlib.Path(options.out)
    written = []

    for bundle in load_bundles(options.project):
        package = bundle.get("package")
        if not package:
            continue
        platform = TARGET_PLATFORM.get(bundle["target"])
        if platform is None or platform not in PLATFORM_SUFFIX:
            continue
        suffix = PLATFORM_SUFFIX[platform]
        candidates = sorted(artifacts.glob(bundle["id"] + "-*" + suffix))
        if not candidates:
            continue
        archive = candidates[0]
        name = package["name"]
        repo_dir = out / options.owner / name
        repo_dir.mkdir(parents=True, exist_ok=True)
        readme = repo_dir / "README.md"
        if not readme.exists():
            readme.write_text("# " + name + "\n\nPackage metadata for " + name + ".\n")
        platform_dir = repo_dir / options.version / platform
        platform_dir.mkdir(parents=True, exist_ok=True)
        url = "/".join([
            options.asset_base.rstrip("/"),
            archive.name,
        ])
        metadata = {
            "name": name,
            "version": options.version,
            "license": package.get("license", "MIT"),
            "repository": options.owner + "/" + options.repo,
            "tag": "v" + options.version,
        }
        if platform == "maven":
            # The registry reads a group id and one entry per published file.
            metadata["groupId"] = name
            metadata["artifacts"] = [
                {"file": entry.name, "url": "/".join([options.asset_base.rstrip("/"), entry.name])}
                for entry in sorted(artifacts.glob(bundle["id"] + "-*"))
                if entry.suffix in (".jar", ".pom")
            ]
        elif platform == "swift":
            # The registry checks the archive path (registry/Core.hx:513) and
            # writes swift/<scope>/<name>/<version>/Package.swift from this
            # field, so it carries the manifest text rather than a URL.
            import zipfile
            with zipfile.ZipFile(archive) as bundle_zip:
                metadata["packageSwift"] = bundle_zip.read("Package.swift").decode("utf-8")
            metadata["archive"] = "swift/tiqian/" + name + "/" + options.version + ".zip"
            metadata["sha256"] = digest_of(archive, "sha256")
        else:
            metadata["url"] = url
            metadata[PLATFORM_DIGEST[platform]] = digest_of(archive, PLATFORM_DIGEST[platform])
        (platform_dir / "metadata.json").write_text(json.dumps(metadata, sort_keys=True) + "\n")
        written.append((name, platform, archive.name))

    if not written:
        sys.exit("no pack artifacts matched a bundle with package metadata")
    for row in written:
        print("metadata:", *row)


if __name__ == "__main__":
    main()
