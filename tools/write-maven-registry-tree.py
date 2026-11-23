#!/usr/bin/env python3
"""Collect and describe the Maven modules Gradle publishes for the registry.

boring pack writes the registry tree for the nine tiqian-engine coordinates.
The platform modules build.gradle.kts publishes (the maven unit of
release-manifest.json: tiqian-jvm-skia, the four Android modules,
tiqian-compose and tiqian-compose-material3) come from Gradle instead. A
Kotlin Multiplatform module publishes a root coordinate and one coordinate per
target (tiqian-compose, tiqian-compose-android, tiqian-compose-jvm). A module
owns its root coordinate, named after the module, and the coordinates the
variants of that root's Gradle module metadata (.module) point at through
available-at. Names alone cannot decide this: tiqian-compose-material3 extends
the name tiqian-compose, and would pass as a tiqian-compose target if the
manifest dropped the material3 module.

collect runs in the Maven release job right after the Maven Local preflight.
It copies the module files from the Maven Local repository into
<out>/<artifactId>/<file>, leaving out the tiqian-engine coordinates (pack
owns them), signatures, checksums and maven-metadata files, and requires
every module of the maven unit. The job keeps that directory as an artifact.

write runs in the registry job. It reads the kept directory, writes one
package directory per module in the layout the pack run uses,

    <tree>/<owner>/<module>/README.md
    <tree>/<owner>/<module>/<version>/maven/metadata.json

copies the files to one flat directory under their own names (the release
asset names the metadata `url` points at) and writes SHA256SUMS beside them,
so check-registry-tree.py can hold the tree to the same files. groupId and
license come from each module's POM.

Usage:
    write-maven-registry-tree.py collect --maven-local <repo> --version <version>
        --out <dir> --expect-manifest release-manifest.json
    write-maven-registry-tree.py write --publication <dir> --assets <dir> --tree <out>
        --owner <owner> --repository <owner/repo> --version <version>
        --expect-manifest release-manifest.json
    write-maven-registry-tree.py --selftest

Exit status: 0 done, 1 a publication that disagrees with the release, 2 a
misconfigured invocation.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ElementTree
from pathlib import Path

EXIT_OK = 0
EXIT_PUBLICATION = 1
EXIT_MISCONFIGURED = 2

GROUP_PATH = ("org", "tiqian")
# boring pack writes these coordinates and their registry metadata.
PACK_OWNED_PREFIX = "tiqian-engine"
SKIPPED_SUFFIXES = (".asc", ".md5", ".sha1", ".sha256", ".sha512")
# The POM license names this build writes, in the SPDX form the pack
# metadata records.
LICENSES = {"Mozilla Public License 2.0": "MPL-2.0"}
POM = "{http://maven.apache.org/POM/4.0.0}"


class PublicationError(Exception):
    pass


def expected_modules(manifest: Path) -> list:
    """The module names the Gradle release unit of release-manifest.json lists."""
    document = json.loads(manifest.read_text(encoding="utf-8"))
    names = []
    for unit in document.get("units", []):
        if (unit.get("packageSource") or {}).get("kind") == "gradle":
            names.extend(unit.get("packages", []))
    if not names:
        raise PublicationError("%s lists no Gradle module" % manifest)
    return sorted(set(names))


def target_coordinates(module_file: Path) -> list:
    """The coordinates the variants of a root .module file point at through available-at."""
    if not module_file.is_file():
        return []
    document = json.loads(module_file.read_text(encoding="utf-8"))
    targets = set()
    for variant in document.get("variants", []):
        location = variant.get("available-at")
        if location and location.get("group") == ".".join(GROUP_PATH):
            targets.add(location["module"])
    return sorted(targets)


def published_file(name: str) -> bool:
    return not name.endswith(SKIPPED_SUFFIXES) and not name.startswith("maven-metadata")


def assign(artifact_ids: list, modules: list, module_file) -> dict:
    """Map each module to its root coordinate and the targets its root .module lists.

    module_file(name) is the path of the root coordinate's .module file. Every
    module needs its root coordinate, every target a root lists must be in the
    publication, and every artifactId must belong to exactly one module.
    """
    present = set(artifact_ids)
    missing = [name for name in modules if name not in present]
    if missing:
        raise PublicationError("the publication has no root coordinate for %s" % ", ".join(missing))
    owned = {name: [name] for name in modules}
    owner = {name: name for name in modules}
    for name in modules:
        for target in target_coordinates(module_file(name)):
            if target not in present:
                raise PublicationError("%s points at %s, which the publication lacks" % (name, target))
            if target in owner:
                raise PublicationError("%s is claimed by both %s and %s" % (target, owner[target], name))
            owner[target] = name
            owned[name].append(target)
    stray = sorted(present - set(owner))
    if stray:
        raise PublicationError("no module of the Gradle release unit owns %s" % ", ".join(stray))
    return {name: sorted(ids) for name, ids in owned.items()}


def collect(maven_local: Path, version: str, out: Path, modules: list) -> int:
    group_dir = maven_local.joinpath(*GROUP_PATH)
    if not group_dir.is_dir():
        raise PublicationError("%s holds no %s group" % (maven_local, ".".join(GROUP_PATH)))
    artifact_ids = sorted(path.name for path in group_dir.iterdir()
                          if path.is_dir() and not path.name.startswith(PACK_OWNED_PREFIX))
    assign(artifact_ids, modules, lambda name: group_dir / name / version / ("%s-%s.module" % (name, version)))
    count = 0
    for artifact_id in artifact_ids:
        version_dir = group_dir / artifact_id / version
        if not version_dir.is_dir():
            raise PublicationError("%s has no version %s" % (artifact_id, version))
        files = sorted(path for path in version_dir.iterdir() if path.is_file() and published_file(path.name))
        if not files:
            raise PublicationError("%s %s holds no file" % (artifact_id, version))
        target = out / artifact_id
        target.mkdir(parents=True, exist_ok=True)
        for path in files:
            if not path.name.startswith("%s-%s" % (artifact_id, version)):
                raise PublicationError("%s is not a %s %s file" % (path.name, artifact_id, version))
            shutil.copy2(path, target / path.name)
            count += 1
        print("collected %s %s: %d files" % (artifact_id, version, len(files)))
    return count


def pom_facts(pom: Path) -> tuple:
    root = ElementTree.parse(pom).getroot()
    group = root.findtext(POM + "groupId")
    license_name = root.findtext("%slicenses/%slicense/%sname" % (POM, POM, POM))
    if not group:
        raise PublicationError("%s names no groupId" % pom.name)
    if license_name not in LICENSES:
        raise PublicationError("%s names license %r, which has no SPDX form here" % (pom.name, license_name))
    return group, LICENSES[license_name]


def write(publication: Path, assets: Path, tree: Path, owner: str, repository: str, version: str, modules: list) -> int:
    artifact_ids = sorted(path.name for path in publication.iterdir() if path.is_dir())
    owned = assign(artifact_ids, modules, lambda name: publication / name / ("%s-%s.module" % (name, version)))
    assets.mkdir(parents=True, exist_ok=True)
    sums = []
    described = []
    for module in modules:
        artifacts = []
        group = license_id = None
        for artifact_id in owned[module]:
            files = sorted(path for path in (publication / artifact_id).iterdir() if path.is_file())
            poms = [path for path in files if path.name == "%s-%s.pom" % (artifact_id, version)]
            if not poms:
                raise PublicationError("%s has no %s POM" % (artifact_id, version))
            pom_group, pom_license = pom_facts(poms[0])
            if group is not None and (pom_group, pom_license) != (group, license_id):
                raise PublicationError("%s disagrees with the other %s coordinates on groupId or license" % (artifact_id, module))
            group, license_id = pom_group, pom_license
            for path in files:
                if not published_file(path.name):
                    raise PublicationError("%s is a signature, checksum or metadata file" % path.name)
                if (assets / path.name).exists():
                    raise PublicationError("two coordinates ship a file named %s" % path.name)
                shutil.copy2(path, assets / path.name)
                sums.append("%s  %s\n" % (hashlib.sha256(path.read_bytes()).hexdigest(), path.name))
                artifacts.append({
                    "artifactId": artifact_id,
                    "file": path.name,
                    "url": "https://github.com/%s/releases/download/v%s/%s" % (repository, version, path.name),
                })
        described.append((module, {
            "name": module,
            "version": version,
            "groupId": group,
            "license": license_id,
            "repository": repository,
            "tag": "v" + version,
            "artifacts": artifacts,
        }))
    for module, metadata in described:
        package_dir = tree / owner / module
        platform_dir = package_dir / version / "maven"
        platform_dir.mkdir(parents=True, exist_ok=True)
        (platform_dir / "metadata.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        (package_dir / "README.md").write_text("# %s\n\nPackage metadata for %s.\n" % (module, module), encoding="utf-8")
        print("wrote %s %s: %d files" % (module, version, len(metadata["artifacts"])))
    (assets / "SHA256SUMS").write_text("".join(sums), encoding="utf-8")
    return len(sums)


def fake_pom(path: Path, artifact_id: str, version: str, license_name: str = "Mozilla Public License 2.0") -> None:
    path.write_text(
        '<?xml version="1.0"?>\n<project xmlns="http://maven.apache.org/POM/4.0.0">'
        "<groupId>org.tiqian</groupId><artifactId>%s</artifactId><version>%s</version>"
        "<licenses><license><name>%s</name></license></licenses></project>\n" % (artifact_id, version, license_name),
        encoding="utf-8",
    )


def selftest() -> int:
    version = "1.0.0"
    modules = ["tiqian-android-view", "tiqian-compose", "tiqian-compose-material3"]
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        repo = root / "m2"
        group = repo / "org" / "tiqian"
        layout = {
            "tiqian-android-view": [".aar", ".pom", "-sources.jar", ".pom.asc"],
            "tiqian-compose": [".jar", ".pom", ".module", "-kotlin-tooling-metadata.json"],
            "tiqian-compose-jvm": [".jar", ".pom", ".module.sha1"],
            "tiqian-compose-material3": [".jar", ".pom", ".module"],
            "tiqian-compose-material3-android": [".aar", ".pom"],
            "tiqian-engine-jvm": [".jar", ".pom"],
        }
        targets = {"tiqian-compose": ["tiqian-compose-jvm"], "tiqian-compose-material3": ["tiqian-compose-material3-android"]}
        for artifact_id, suffixes in layout.items():
            version_dir = group / artifact_id / version
            version_dir.mkdir(parents=True)
            (group / artifact_id / "maven-metadata-local.xml").write_text("<metadata/>\n")
            for suffix in suffixes:
                name = "%s-%s%s" % (artifact_id, version, suffix)
                if suffix == ".pom":
                    fake_pom(version_dir / name, artifact_id, version)
                elif suffix == ".module":
                    variants = [{"name": "%sElements" % target, "available-at": {"group": "org.tiqian", "module": target, "version": version}}
                                for target in targets.get(artifact_id, [])]
                    (version_dir / name).write_text(json.dumps({"formatVersion": "1.1", "variants": variants}))
                else:
                    (version_dir / name).write_text(name)
        out = root / "publication"
        assert collect(repo, version, out, modules) == 14
        assert not (out / "tiqian-engine-jvm").exists()
        assert not list(out.rglob("*.asc")) and not list(out.rglob("*.sha1"))
        assets = root / "assets"
        tree = root / "tree"
        assert write(out, assets, tree, "tiqian-cjk", "tiqian-cjk/tiqian", version, modules) == 14
        compose = json.loads((tree / "tiqian-cjk" / "tiqian-compose" / version / "maven" / "metadata.json").read_text())
        assert compose["groupId"] == "org.tiqian" and compose["license"] == "MPL-2.0"
        assert sorted({item["artifactId"] for item in compose["artifacts"]}) == ["tiqian-compose", "tiqian-compose-jvm"]
        material = json.loads((tree / "tiqian-cjk" / "tiqian-compose-material3" / version / "maven" / "metadata.json").read_text())
        assert sorted({item["artifactId"] for item in material["artifacts"]}) == ["tiqian-compose-material3", "tiqian-compose-material3-android"]
        assert compose["artifacts"][0]["url"].startswith("https://github.com/tiqian-cjk/tiqian/releases/download/v1.0.0/")
        assert len((assets / "SHA256SUMS").read_text().splitlines()) == 14
        try:
            collect(repo, version, root / "partial", modules + ["tiqian-android-shaping"])
            raise AssertionError("a missing module was accepted")
        except PublicationError as error:
            assert "tiqian-android-shaping" in str(error)
        try:
            collect(repo, version, root / "dropped", ["tiqian-android-view", "tiqian-compose"])
            raise AssertionError("a module missing from the manifest passed as a target of another")
        except PublicationError as error:
            assert "tiqian-compose-material3" in str(error)
        (group / "tiqian-stray" / version).mkdir(parents=True)
        try:
            collect(repo, version, root / "stray", modules)
            raise AssertionError("an unknown artifactId was accepted")
        except PublicationError as error:
            assert "owns tiqian-stray" in str(error)
    print("selftest: OK")
    return EXIT_OK


def main(argv: list) -> int:
    if argv == ["--selftest"]:
        return selftest()
    parser = argparse.ArgumentParser(description="Collect and describe the Gradle Maven publication for the registry.")
    commands = parser.add_subparsers(dest="command", required=True)
    collect_parser = commands.add_parser("collect")
    collect_parser.add_argument("--maven-local", type=Path, required=True)
    collect_parser.add_argument("--version", required=True)
    collect_parser.add_argument("--out", type=Path, required=True)
    collect_parser.add_argument("--expect-manifest", type=Path, required=True)
    write_parser = commands.add_parser("write")
    write_parser.add_argument("--publication", type=Path, required=True)
    write_parser.add_argument("--assets", type=Path, required=True)
    write_parser.add_argument("--tree", type=Path, required=True)
    write_parser.add_argument("--owner", required=True)
    write_parser.add_argument("--repository", required=True)
    write_parser.add_argument("--version", required=True)
    write_parser.add_argument("--expect-manifest", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        modules = expected_modules(args.expect_manifest)
        if args.command == "collect":
            count = collect(args.maven_local, args.version, args.out, modules)
        else:
            if not args.publication.is_dir():
                print("MISCONFIGURED: publication directory is missing: %s" % args.publication)
                return EXIT_MISCONFIGURED
            count = write(args.publication, args.assets, args.tree, args.owner, args.repository, args.version, modules)
    except PublicationError as error:
        print("FAIL: %s" % error)
        return EXIT_PUBLICATION
    print("%s: OK (%d files)" % (args.command, count))
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
