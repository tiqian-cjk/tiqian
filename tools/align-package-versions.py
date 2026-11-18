#!/usr/bin/env python3
"""Set every package version in the repository to the release version.

One release tag carries one version. The tag is the only version source: the
registry derives artifact names from <package>-<version>, and every npm lane
publishes the version its manifest declares, so the packages published by a
tag must all carry the tag version.

This script is the single writer for the npm manifests. The project file keeps
its placeholder until the pack job runs, because the generated bundles are
rewritten in the pack checkout; the npm manifests are rewritten before the tag
so the tagged commit can locate every handwritten package version.

Usage:
    align-package-versions.py <version> [project path]
    align-package-versions.py --npm <version>
    align-package-versions.py --check <version>

The first form rewrites the project file (boring.json) and every npm manifest.
--npm rewrites only the npm manifests, which is the release preparation step
that runs before the release tag. --check writes nothing and exits 1 when an
npm manifest or an internal dependency pin does not carry the version; the
release gate calls it on the tagged commit.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEPENDENCY_FIELDS = (
    "dependencies",
    "devDependencies",
    "peerDependencies",
    "optionalDependencies",
)
USAGE = "usage: align-package-versions.py [--npm | --check] <version> [project]"


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def strip_line_comments(text):
    return re.sub(r"(?m)^[ \t]*//.*$", "", text)


def project_document(project):
    return json.loads(strip_line_comments(project.read_text(encoding="utf-8")))


def npm_manifests(root):
    """Every npm manifest that carries a release version.

    The workspace list of the root manifest names the workspace packages; the
    release manifest names the packages that are not workspaces (the four
    platform addons) and the packages outside the version release.
    """
    paths = []
    root_manifest = read_json(root / "package.json")
    for relative in root_manifest.get("workspaces", []):
        candidate = root / relative / "package.json"
        if candidate.is_file():
            paths.append(candidate)
    release = read_json(root / "release-manifest.json")
    sources = [unit.get("packageSource") or {} for unit in release.get("units", [])]
    for item in release.get("notInRelease", []):
        sources.append({"kind": "npm", "files": [item.get("file", "")]})
    for source in sources:
        if source.get("kind") != "npm":
            continue
        for relative in source.get("files", []):
            candidate = root / relative
            if candidate.is_file():
                paths.append(candidate)
    return sorted(set(paths))


def internal_packages(root, manifests, project):
    """The names whose version moves with the release.

    A dependency on any of these names inside the repository pins one release
    version; an install of the packed tarballs resolves that version, so the
    pin has to move with the release.
    """
    names = set()
    for path in manifests:
        name = read_json(path).get("name")
        if name:
            names.add(name)
    for bundle in project_document(project).get("bundles", []):
        name = (bundle.get("package") or {}).get("name")
        if name:
            names.add(name)
    return names


def manifest_problems(root, manifests, names, version):
    problems = []
    for path in manifests:
        document = read_json(path)
        label = path.relative_to(root).as_posix()
        if document.get("version") != version:
            problems.append(
                "%s: version %s, expected %s" % (label, document.get("version"), version)
            )
        for field in DEPENDENCY_FIELDS:
            dependencies = document.get(field)
            if not isinstance(dependencies, dict):
                continue
            for dependency, specifier in dependencies.items():
                if dependency not in names:
                    continue
                if isinstance(specifier, str) and specifier.startswith("workspace:"):
                    continue
                if specifier != version:
                    problems.append(
                        "%s: %s/%s is %s, expected %s"
                        % (label, field, dependency, specifier, version)
                    )
    return problems


def lockfile_entries(root, manifests):
    """The package-lock.json entries that mirror an npm manifest.

    npm records each workspace package's version in the root lockfile, and an
    install resolves the lockfile copy. A release that moves the manifests and
    leaves the lockfile behind publishes manifests whose lock disagrees, so the
    lockfile is part of the same rewrite.
    """
    lock = root / "package-lock.json"
    if not lock.is_file():
        return lock, None
    document = read_json(lock)
    packages = document.get("packages")
    if not isinstance(packages, dict):
        return lock, None
    entries = []
    for path in manifests:
        relative = path.parent.relative_to(root).as_posix()
        entry = packages.get(relative)
        if isinstance(entry, dict) and "version" in entry:
            entries.append((relative, entry))
    return lock, document


def lockfile_problems(root, manifests, names, version):
    lock, document = lockfile_entries(root, manifests)
    if document is None:
        return []
    problems = []
    for path in manifests:
        relative = path.parent.relative_to(root).as_posix()
        entry = document["packages"].get(relative)
        if not isinstance(entry, dict):
            continue
        if entry.get("version") != version:
            problems.append(
                "%s: package-lock.json holds version %s, expected %s"
                % (relative, entry.get("version"), version)
            )
        for field in DEPENDENCY_FIELDS:
            dependencies = entry.get(field)
            if not isinstance(dependencies, dict):
                continue
            for dependency, specifier in dependencies.items():
                if dependency not in names or not isinstance(specifier, str):
                    continue
                if specifier.startswith("workspace:"):
                    continue
                if specifier != version:
                    problems.append(
                        "%s: package-lock.json %s/%s is %s, expected %s"
                        % (relative, field, dependency, specifier, version)
                    )
    return problems


def align_lockfile(root, manifests, names, version):
    lock, document = lockfile_entries(root, manifests)
    if document is None:
        return 0
    changed = 0
    for path in manifests:
        relative = path.parent.relative_to(root).as_posix()
        entry = document["packages"].get(relative)
        if not isinstance(entry, dict):
            continue
        if entry.get("version") != version:
            entry["version"] = version
            changed += 1
        for field in DEPENDENCY_FIELDS:
            dependencies = entry.get(field)
            if not isinstance(dependencies, dict):
                continue
            for dependency, specifier in dependencies.items():
                if dependency not in names or not isinstance(specifier, str):
                    continue
                if specifier.startswith("workspace:"):
                    continue
                if specifier != version:
                    dependencies[dependency] = version
                    changed += 1
    if changed:
        lock.write_text(json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return changed


def align_manifests(root, manifests, names, version):
    for path in manifests:
        document = read_json(path)
        document["version"] = version
        for field in DEPENDENCY_FIELDS:
            dependencies = document.get(field)
            if not isinstance(dependencies, dict):
                continue
            for dependency, specifier in dependencies.items():
                if dependency not in names:
                    continue
                if isinstance(specifier, str) and specifier.startswith("workspace:"):
                    continue
                dependencies[dependency] = version
        path.write_text(
            json.dumps(document, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )


def align_project(project, version):
    """Rewrite the version of every bundle that declares a package."""
    text = project.read_text(encoding="utf-8")

    def bump(match):
        body = match.group(0)
        return re.sub(r'"version": "[^"]*"', '"version": "%s"' % version, body, count=1)

    updated = re.sub(r'"package":\s*\{[^{}]*\}', bump, text)
    project.write_text(updated, encoding="utf-8")
    clean = strip_line_comments(updated)
    json.loads(clean)
    bundles = [bundle for bundle in json.loads(clean)["bundles"] if "package" in bundle]
    return len(bundles)


def main(argv):
    mode = "all"
    if argv and argv[0] in ("--npm", "--check"):
        mode = argv[0][2:]
        argv = argv[1:]
    if not argv:
        sys.exit(USAGE)
    version = argv[0]
    project = pathlib.Path(argv[1]) if len(argv) > 1 else ROOT / "boring.json"
    manifests = npm_manifests(ROOT)
    names = internal_packages(ROOT, manifests, project)

    if mode == "check":
        problems = manifest_problems(ROOT, manifests, names, version)
        problems.extend(lockfile_problems(ROOT, manifests, names, version))
        for problem in problems:
            print("MISMATCH: %s" % problem)
        if problems:
            print("check: FAIL (%d)" % len(problems))
            return 1
        print("check: OK (%d npm manifests at %s)" % (len(manifests), version))
        return 0

    align_manifests(ROOT, manifests, names, version)
    locked = align_lockfile(ROOT, manifests, names, version)
    if mode == "npm":
        print("aligned %d npm manifests and %d lockfile entries to %s" % (len(manifests), locked, version))
        return 0
    bundles = align_project(project, version)
    print("aligned %d packages to %s" % (bundles, version))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
