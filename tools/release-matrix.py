#!/usr/bin/env python3
"""Build the release matrix from boring.json and check it for gaps.

The bundle list in boring.json is the only input. Every bundle that declares
package metadata is packed by boring pack, and the bundle target selects the
ecosystem whose registry receives the artifact. This script derives that
mapping, the artifact path each ecosystem consumes, and the state of each
ecosystem (enabled, or explicitly not enabled with a reason). The target to
ecosystem mapping lives here; no other tool in the repository holds it.

Usage:
    release-matrix.py --check [--project boring.json]
    release-matrix.py --list-bundles [--project boring.json]
    release-matrix.py --matrix [--project boring.json]
    release-matrix.py --pack-matrix [--project boring.json]
    release-matrix.py --json [--project boring.json]

Exit status: 0 the check passed, 1 the check found a gap, 2 the project file
or the script configuration is unusable.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

EXIT_OK = 0
EXIT_GAP = 1
EXIT_MISCONFIGURED = 2

# The five ecosystems the bundles feed. A target outside this map has no
# registry, so the check fails instead of dropping the bundle.
TARGET_ECOSYSTEM = {
    "kotlin": "maven",
    "ts": "npm",
    "swift": "swift",
    "dart": "pub",
    "rust": "cargo",
}

# Every ecosystem the bundles use states whether the release publishes to its
# official registry. "not-enabled" requires a reason, and the check fails when
# an ecosystem has no entry at all.
ECOSYSTEM_STATE = {
    "npm": {
        "state": "enabled",
        "note": "registry.npmjs.org: OIDC trusted publishing, NPM_DIST_TAG_TOKEN for the latest tag",
    },
    "maven": {
        "state": "enabled",
        "note": "Central staging is published by Gradle while the multi-artifact registry model is pending",
    },
    "swift": {
        "state": "enabled",
        "note": "no central registry: the zip goes to R2 and the registry site serves the SwiftPM endpoints",
    },
    "cargo": {
        "state": "not-enabled",
        "reason": "crates.io name availability and CARGO_DIST_TOKEN are unconfirmed",
    },
    "pub": {
        "state": "not-enabled",
        "reason": "pub.dev credentials and the tiqian_engine name are unconfirmed",
    },
}

# Bundles the pack job leaves out, each with the reason the check accepts. A
# bundle that is neither published by its ecosystem nor listed here fails the
# check, so an unclaimed bundle cannot drop out of the release without a
# recorded decision.
EXCLUDED_BUNDLES = {
    # The shared Rust crate is a path dependency of platforms/web/server/precompute;
    # it is not a registry artifact.
    "shared-rust": "path dependency of the Rust precompute crate",
}

# The install artifact each target writes beside its output tree
# (boring packages/compiler/PackageArtifacts.hx). Maven writes a repository
# directory instead of one archive, so it has its own branch.
SUFFIX = {"npm": ".tgz", "cargo": ".crate", "pub": ".tar.gz", "swift": ".zip"}


class Misconfigured(Exception):
    """The project file or the script tables cannot produce a matrix."""


def strip_line_comments(text: str) -> str:
    return re.sub(r"(?m)^[ \t]*//.*$", "", text)


def read_project(path: pathlib.Path) -> dict:
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        raise Misconfigured("missing project file: %s" % path)
    try:
        return json.loads(strip_line_comments(text))
    except json.JSONDecodeError as error:
        raise Misconfigured("%s is not valid JSON: %s" % (path, error))


def define_value(bundle: dict, name: str):
    """The value of -D <name>=<value> in the bundle haxeArgs, or None."""
    args = bundle.get("haxeArgs") or []
    for index, arg in enumerate(args):
        if arg == "-D" and index + 1 < len(args) and args[index + 1].startswith(name + "="):
            return args[index + 1].split("=", 1)[1]
        if arg.startswith("-D" + name + "="):
            return arg.split("=", 1)[1]
    return None


def package_of(bundle: dict) -> dict:
    return bundle.get("package") or {}


def artifact_stem(bundle: dict) -> str:
    return define_value(bundle, "package-artifact-stem") or package_of(bundle).get("name", "")


def published_name(bundle: dict, ecosystem: str) -> str:
    """The name the ecosystem registry resolves the package under.

    boring reads the ecosystem-specific name for the target
    (`Config.ecosystemName`): an npm target publishes the `npmName` when the
    bundle states one, so @tiqian/engine reaches registry.npmjs.org even
    though the shared `name` is tiqian-engine. The registry name and the
    artifact file name both follow the name boring writes into the manifest;
    a matrix that guesses the shared name disagrees with the pack output.
    """
    package = package_of(bundle)
    if ecosystem == "npm":
        return package.get("npmName") or package.get("name", "")
    if ecosystem in ("maven", "swift"):
        return artifact_stem(bundle)
    if ecosystem == "pub":
        return package.get("name", "").replace("-", "_")
    return package.get("name", "")


def file_stem(bundle: dict, ecosystem: str) -> str:
    """The install artifact's file name stem, as the pack writes it.

    `PackageArtifacts` joins the artifact stem with the version and replaces
    "/" with "-", so the scoped npm name @tiqian/engine is packed as
    @tiqian-engine-<version>.tgz. The Pub archive names its package with
    underscores; the packed pubspec carries the same form.
    """
    if ecosystem == "npm":
        return published_name(bundle, "npm").replace("/", "-")
    stem = artifact_stem(bundle)
    return stem.replace("-", "_") if ecosystem == "pub" else stem


def registry_name(bundle: dict, ecosystem: str) -> str:
    return published_name(bundle, ecosystem)


def artifact_paths(project: dict, bundle: dict, ecosystem: str, version: str) -> list:
    out_root = project.get("outRoot", "engine-haxe/out")
    package = package_of(bundle)
    stem = artifact_stem(bundle)
    base = "%s/%s" % (out_root, bundle["id"])
    if ecosystem == "maven":
        group = define_value(bundle, "package-group") or package.get("name", "")
        directory = "%s/maven/%s/%s/%s" % (base, group.replace(".", "/"), stem, version)
        return [
            "%s/%s-%s.jar" % (directory, stem, version),
            "%s/%s-%s.pom" % (directory, stem, version),
        ]
    name = file_stem(bundle, ecosystem)
    return ["%s/%s-%s%s" % (base, name, version, SUFFIX[ecosystem])]


def build_matrix(path: pathlib.Path, version: str | None = None) -> dict:
    project = read_project(path)
    bundles = project.get("bundles")
    if not bundles:
        raise Misconfigured("%s declares no bundle" % path)
    entries = []
    for bundle in bundles:
        if not bundle.get("id"):
            raise Misconfigured("%s has a bundle without an id" % path)
        ecosystem = TARGET_ECOSYSTEM.get(bundle.get("target"))
        state = ECOSYSTEM_STATE.get(ecosystem, {}) if ecosystem else {}
        excluded = bundle["id"] in EXCLUDED_BUNDLES
        release_version = version or package_of(bundle).get("version", "")
        entries.append(
            {
                "id": bundle["id"],
                "target": bundle.get("target"),
                "ecosystem": ecosystem,
                "package": package_of(bundle).get("name"),
                "version": release_version,
                "license": package_of(bundle).get("license"),
                "artifactStem": artifact_stem(bundle),
                "registryName": registry_name(bundle, ecosystem) if ecosystem else None,
                "artifacts": artifact_paths(project, bundle, ecosystem, release_version) if ecosystem else [],
                "excluded": excluded,
                "exclusionReason": EXCLUDED_BUNDLES.get(bundle["id"], ""),
                "packed": not excluded,
                "official": (not excluded) and state.get("state") == "enabled",
            }
        )
    return {
        "project": str(path),
        "releaseVersion": version or "",
        "outRoot": project.get("outRoot", "engine-haxe/out"),
        "ecosystems": ECOSYSTEM_STATE,
        "bundles": entries,
        "packBundles": [entry["id"] for entry in entries if not entry["excluded"]],
    }


def check_matrix(matrix: dict, path: pathlib.Path) -> list:
    failures = []
    entries = matrix["bundles"]
    ids = [entry["id"] for entry in entries]
    if len(ids) != len(set(ids)):
        failures.append("duplicate bundle id in %s" % path)
    seen_keys = {}
    for entry in entries:
        label = "bundle %s" % entry["id"]
        if not entry["ecosystem"]:
            failures.append(
                "%s: target %r has no ecosystem; add it to TARGET_ECOSYSTEM or fix the target"
                % (label, entry["target"])
            )
            continue
        state = ECOSYSTEM_STATE.get(entry["ecosystem"])
        if not state:
            failures.append(
                "%s: ecosystem %s has no state; add it to ECOSYSTEM_STATE as enabled or not-enabled"
                % (label, entry["ecosystem"])
            )
            continue
        if state.get("state") not in ("enabled", "not-enabled"):
            failures.append(
                "%s: ecosystem %s states %r; use enabled or not-enabled"
                % (label, entry["ecosystem"], state.get("state"))
            )
        if state.get("state") == "not-enabled" and not state.get("reason"):
            failures.append("%s: ecosystem %s is not enabled without a reason" % (label, entry["ecosystem"]))
        if not entry["package"] or not entry["version"] or not entry["license"]:
            failures.append("%s: package name, version and license are all required" % label)
        if entry["excluded"] and not entry["exclusionReason"]:
            failures.append("%s: excluded without a reason" % label)
        if not entry["official"]:
            covered = entry["excluded"] or state.get("state") == "not-enabled"
            if not covered:
                failures.append(
                    "%s: not published and not excluded; declare the decision in EXCLUDED_BUNDLES with a reason"
                    % label
                )
        if entry["packed"] and entry["ecosystem"] and entry["registryName"] and entry["version"]:
            key = (entry["ecosystem"], entry["registryName"], entry["version"])
            prior = seen_keys.get(key)
            if prior is not None and prior["stem"] != entry["artifactStem"]:
                failures.append(
                    "%s: %s/%s/%s is already written by bundle %s with artifact stem %s; "
                    "one of the two bundles needs an explicit exclusion"
                    % (label, key[0], key[1], key[2], prior["id"], prior["stem"])
                )
            elif prior is None:
                seen_keys[key] = {"id": entry["id"], "stem": entry["artifactStem"]}
    declared = set(ids)
    stale = sorted(set(EXCLUDED_BUNDLES) - declared)
    for bundle_id in stale:
        failures.append("exclusion %s names a bundle that boring.json does not declare" % bundle_id)
    return failures


def report(matrix: dict, failures: list) -> None:
    entries = matrix["bundles"]
    packed = [entry["id"] for entry in entries if entry["packed"]]
    official = [entry["id"] for entry in entries if entry["official"]]
    print("project: %s" % matrix["project"])
    print("bundles: %d" % len(entries))
    states = []
    for name in sorted({entry["ecosystem"] for entry in entries if entry["ecosystem"]}):
        state = ECOSYSTEM_STATE[name]
        if state["state"] == "enabled":
            states.append("%s (enabled)" % name)
        else:
            states.append("%s (not-enabled: %s)" % (name, state.get("reason", "")))
    print("ecosystems: %s" % ", ".join(states))
    print("packed for the registry: %d (%s)" % (len(packed), ", ".join(packed)))
    print("published to official registries: %d (%s)" % (len(official), ", ".join(official)))
    for entry in entries:
        if not entry["packed"]:
            print("not packed: %s (%s)" % (entry["id"], entry["exclusionReason"]))
    for entry in entries:
        if entry["packed"] and not entry["official"]:
            reason = ECOSYSTEM_STATE.get(entry["ecosystem"], {}).get("reason", "")
            print("not published to the official registry: %s (%s)" % (entry["id"], reason))
    if failures:
        for failure in failures:
            print("FAIL: %s" % failure)
        print("check: FAIL (%d)" % len(failures))
    else:
        print("check: OK")


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description="Derive and check the tiqian release matrix.")
    parser.add_argument("--project", type=pathlib.Path, default=pathlib.Path("boring.json"))
    parser.add_argument("--version", default=None, help="release version for artifact names; boring.json holds the placeholder")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--list-bundles", action="store_true")
    parser.add_argument("--matrix", action="store_true")
    parser.add_argument("--pack-matrix", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)
    try:
        matrix = build_matrix(args.project, args.version)
    except Misconfigured as error:
        print("MISCONFIGURED: %s" % error)
        return EXIT_MISCONFIGURED
    if args.list_bundles:
        for bundle_id in matrix["packBundles"]:
            print(bundle_id)
        return EXIT_OK
    if args.pack_matrix:
        # Keep each registry ecosystem together. Cargo and pub share a runner.
        shards: dict[str, list[str]] = {}
        for entry in matrix["bundles"]:
            if entry["packed"]:
                shard = "sources" if entry["ecosystem"] in ("cargo", "pub") else entry["ecosystem"]
                shards.setdefault(shard, []).append(entry["id"])

        # Publish jobs consume the Web inputs without waiting for other shards.
        print(json.dumps({
            "web": " ".join(shards.pop("npm", [])),
            "include": [{"shard": shard, "bundles": " ".join(ids)} for shard, ids in shards.items()],
        }))
        return EXIT_OK
    if args.matrix:
        include = [
            {
                "bundle": entry["id"],
                "ecosystem": entry["ecosystem"],
                "package": entry["package"],
                "version": entry["version"],
                "registryName": entry["registryName"],
                "packed": entry["packed"],
                "official": entry["official"],
            }
            for entry in matrix["bundles"]
            if not entry["excluded"]
        ]
        print(json.dumps({"include": include}, sort_keys=True))
        return EXIT_OK
    if args.json:
        print(json.dumps(matrix, indent=2, sort_keys=True))
        return EXIT_OK
    if not args.check:
        parser.error("choose --check, --list-bundles, --matrix, --pack-matrix or --json")
    failures = check_matrix(matrix, args.project)
    report(matrix, failures)
    return EXIT_GAP if failures else EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

