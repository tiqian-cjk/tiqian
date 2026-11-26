#!/usr/bin/env python3
"""Write registry metadata for the npm tarballs the Web lanes published.

The boring pack run writes the registry tree for the engine bundles. The Web
packages (@tiqian/engine, core, web-component, precompute and its platform
packages, and the framework adapters) are packed and published by their own
lanes, each of which keeps the tarball it handed to npm as an npm-tarball-*
artifact. The registry lane downloads those artifacts, uploads the files to
the GitHub release, and runs this script to describe them in the same tree
layout the pack run uses:

    <tree>/<owner>/<name, slash as %2f>/README.md
    <tree>/<owner>/<name, slash as %2f>/<version>/npm/metadata.json

Every value comes from the tarball itself: name, version and license from its
package/package.json, sha512 from its bytes, and `manifest` from the
package.json resolution fields, which the registry copies into the packument
so npm installs the dependencies. The `url` names the release asset the
registry lane uploads under the tarball's own file name. The script also
writes SHA256SUMS beside the tarballs, so check-registry-tree.py can hold the
written tree to the same files.

With --expect-manifest the script reads release-manifest.json and requires
the tarballs to pack exactly the packages its npm units list, so a lane that
kept no tarball fails the registry write instead of leaving a package out
that the others depend on. Nothing is written when the set differs.

Usage:
    write-npm-registry-tree.py --tarballs <dir> --tree <out> --owner <owner>
        --repository <owner/repo> --version <version>
        [--expect-manifest release-manifest.json]
    write-npm-registry-tree.py --selftest

Exit status: 0 written, 1 a tarball that disagrees with the release,
2 a misconfigured invocation.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
import sys
import tarfile
import tempfile
from pathlib import Path

EXIT_OK = 0
EXIT_TARBALL = 1
EXIT_MISCONFIGURED = 2

# The package.json fields npm resolves from the packument version entry, in
# the order boring's registry tool accepts under `manifest`.
MANIFEST_KEYS = [
    "dependencies",
    "optionalDependencies",
    "peerDependencies",
    "peerDependenciesMeta",
    "bin",
    "engines",
    "os",
    "cpu",
]


class TarballError(Exception):
    pass


def package_json(tarball: Path) -> dict:
    with tarfile.open(tarball, "r:gz") as archive:
        try:
            member = archive.getmember("package/package.json")
        except KeyError:
            raise TarballError("%s holds no package/package.json" % tarball.name)
        handle = archive.extractfile(member)
        if handle is None:
            raise TarballError("%s: package/package.json is not a regular file" % tarball.name)
        return json.loads(handle.read().decode("utf-8"))


def describe(tarball: Path, repository: str, version: str) -> tuple:
    manifest = package_json(tarball)
    name = manifest.get("name")
    if not isinstance(name, str) or not name:
        raise TarballError("%s: package.json names no package" % tarball.name)
    if manifest.get("version") != version:
        raise TarballError("%s: version %s is not the release version %s" % (tarball.name, manifest.get("version"), version))
    data = tarball.read_bytes()
    metadata = {
        "name": name,
        "version": version,
        "repository": repository,
        "tag": "v" + version,
        "url": "https://github.com/%s/releases/download/v%s/%s" % (repository, version, tarball.name),
        "sha512": base64.b64encode(hashlib.sha512(data).digest()).decode("ascii"),
    }
    license_value = manifest.get("license")
    if isinstance(license_value, str) and license_value:
        metadata["license"] = license_value
    resolution = {key: manifest[key] for key in MANIFEST_KEYS if key in manifest}
    if resolution:
        metadata["manifest"] = resolution
    return name, metadata, hashlib.sha256(data).hexdigest()


def expected_packages(manifest: Path) -> set:
    """The package names the npm release units of release-manifest.json list."""
    document = json.loads(manifest.read_text(encoding="utf-8"))
    names = set()
    for unit in document.get("units", []):
        if (unit.get("packageSource") or {}).get("kind") == "npm":
            names.update(unit.get("packages", []))
    if not names:
        raise TarballError("%s lists no npm package" % manifest)
    return names


def write(tarballs: Path, tree: Path, owner: str, repository: str, version: str, expected: set = None) -> int:
    # The release assets and check-registry-tree.py both name a tarball by its
    # bare file name, so every tarball must sit directly in the directory; the
    # registry lane moves the nested precompute archives up before this runs.
    nested = sorted(path for path in tarballs.rglob("*.tgz") if path.parent != tarballs)
    if nested:
        raise TarballError("%s sits below %s; move every tarball to that directory" % (nested[0], tarballs))
    files = sorted(tarballs.glob("*.tgz"))
    if not files:
        raise TarballError("%s holds no tarball" % tarballs)
    seen_names = {}
    described = []
    for tarball in files:
        name, metadata, sha256 = describe(tarball, repository, version)
        if name in seen_names:
            raise TarballError("%s and %s both pack %s" % (seen_names[name].name, tarball.name, name))
        seen_names[name] = tarball
        described.append((tarball, name, metadata, sha256))
    if expected is not None:
        missing = sorted(expected - set(seen_names))
        extra = sorted(set(seen_names) - expected)
        if missing or extra:
            raise TarballError("the tarballs do not match the npm release units: missing %s, unexpected %s"
                               % (", ".join(missing) or "none", ", ".join(extra) or "none"))
    sums = []
    for tarball, name, metadata, sha256 in described:
        package_dir = tree / owner / name.replace("/", "%2f")
        platform_dir = package_dir / version / "npm"
        platform_dir.mkdir(parents=True, exist_ok=True)
        (platform_dir / "metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        (package_dir / "README.md").write_text("# %s\n\nPackage metadata for %s.\n" % (name, name), encoding="utf-8")
        sums.append("%s  %s\n" % (sha256, tarball.name))
        print("wrote %s %s from %s" % (name, version, tarball.name))
    (tarballs / "SHA256SUMS").write_text("".join(sums), encoding="utf-8")
    return len(files)


def fake_tarball(path: Path, package: dict) -> None:
    body = json.dumps(package).encode("utf-8")
    with tarfile.open(path, "w:gz") as archive:
        info = tarfile.TarInfo("package/package.json")
        info.size = len(body)
        archive.addfile(info, io.BytesIO(body))


def selftest() -> int:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        tarballs = root / "tarballs"
        tarballs.mkdir()
        fake_tarball(tarballs / "tiqian-core-1.0.0.tgz", {
            "name": "@tiqian/core", "version": "1.0.0", "license": "MPL-2.0", "scripts": {"build": "tsc"},
            "dependencies": {"@tiqian/engine": "1.0.0"}, "engines": {"node": ">=22"},
        })
        fake_tarball(tarballs / "tiqian-precompute-linux-x64-gnu-1.0.0.tgz", {
            "name": "@tiqian/precompute-linux-x64-gnu", "version": "1.0.0", "os": ["linux"], "cpu": ["x64"],
        })
        tree = root / "tree"
        assert write(tarballs, tree, "tiqian-cjk", "tiqian-cjk/tiqian", "1.0.0") == 2
        core = json.loads((tree / "tiqian-cjk" / "@tiqian%2fcore" / "1.0.0" / "npm" / "metadata.json").read_text())
        assert core["url"] == "https://github.com/tiqian-cjk/tiqian/releases/download/v1.0.0/tiqian-core-1.0.0.tgz"
        assert core["manifest"] == {"dependencies": {"@tiqian/engine": "1.0.0"}, "engines": {"node": ">=22"}}
        assert core["license"] == "MPL-2.0"
        assert core["sha512"] == base64.b64encode(hashlib.sha512((tarballs / "tiqian-core-1.0.0.tgz").read_bytes()).digest()).decode()
        native = json.loads((tree / "tiqian-cjk" / "@tiqian%2fprecompute-linux-x64-gnu" / "1.0.0" / "npm" / "metadata.json").read_text())
        assert native["manifest"] == {"os": ["linux"], "cpu": ["x64"]} and "license" not in native
        assert (tree / "tiqian-cjk" / "@tiqian%2fcore" / "README.md").read_text() == "# @tiqian/core\n\nPackage metadata for @tiqian/core.\n"
        assert len((tarballs / "SHA256SUMS").read_text().splitlines()) == 2
        fake_tarball(tarballs / "tiqian-engine-0.9.0.tgz", {"name": "@tiqian/engine", "version": "0.9.0"})
        try:
            write(tarballs, root / "tree2", "tiqian-cjk", "tiqian-cjk/tiqian", "1.0.0")
            raise AssertionError("a tarball of another version was accepted")
        except TarballError as error:
            assert "0.9.0" in str(error)
        (tarballs / "tiqian-engine-0.9.0.tgz").unlink()
        (tarballs / "main-package").mkdir()
        fake_tarball(tarballs / "main-package" / "tiqian-precompute-1.0.0.tgz", {"name": "@tiqian/precompute", "version": "1.0.0"})
        try:
            write(tarballs, root / "tree3", "tiqian-cjk", "tiqian-cjk/tiqian", "1.0.0")
            raise AssertionError("a nested tarball was accepted")
        except TarballError as error:
            assert "main-package" in str(error)
        (tarballs / "main-package" / "tiqian-precompute-1.0.0.tgz").unlink()
        manifest = root / "release-manifest.json"
        manifest.write_text(json.dumps({"units": [
            {"id": "npm-core", "packageSource": {"kind": "npm"}, "packages": ["@tiqian/core"]},
            {"id": "npm-precompute", "packageSource": {"kind": "npm"},
             "packages": ["@tiqian/precompute-linux-x64-gnu", "@tiqian/precompute"]},
            {"id": "maven", "packageSource": {"kind": "gradle"}, "packages": ["tiqian-compose"]},
        ]}))
        try:
            write(tarballs, root / "tree4", "tiqian-cjk", "tiqian-cjk/tiqian", "1.0.0", expected_packages(manifest))
            raise AssertionError("a missing package was accepted")
        except TarballError as error:
            assert "missing @tiqian/precompute," in str(error) and "unexpected none" in str(error)
            assert not (root / "tree4").exists()
        fake_tarball(tarballs / "tiqian-precompute-1.0.0.tgz", {"name": "@tiqian/precompute", "version": "1.0.0"})
        assert write(tarballs, root / "tree5", "tiqian-cjk", "tiqian-cjk/tiqian", "1.0.0", expected_packages(manifest)) == 3
    print("selftest: OK")
    return EXIT_OK


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description="Write registry metadata for published npm tarballs.")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--tarballs", type=Path)
    parser.add_argument("--tree", type=Path)
    parser.add_argument("--owner")
    parser.add_argument("--repository")
    parser.add_argument("--version")
    parser.add_argument("--expect-manifest", type=Path)
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    if not (args.tarballs and args.tree and args.owner and args.repository and args.version):
        parser.print_usage()
        return EXIT_MISCONFIGURED
    if not args.tarballs.is_dir():
        print("MISCONFIGURED: tarball directory is missing: %s" % args.tarballs)
        return EXIT_MISCONFIGURED
    try:
        expected = expected_packages(args.expect_manifest) if args.expect_manifest else None
        count = write(args.tarballs, args.tree, args.owner, args.repository, args.version, expected)
    except TarballError as error:
        print("FAIL: %s" % error)
        return EXIT_TARBALL
    print("write: OK (%d tarballs)" % count)
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
