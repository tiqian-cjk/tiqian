#!/usr/bin/env python3
"""Release gate for tiqian.

One release tag must not publish a partial version. Every package the
repository publishes is declared in release-manifest.json, and every package
must be reachable from the single release entrypoint. Before the entrypoint
publishes anything, this gate requires each lane under release.requiredLanes
to have a completed, successful workflow run on the release commit.

The gate refuses when a lane is red, when a lane has not run on the release
commit at all, and when a lane is still queued or running. A missing run is
not evidence of success. A --sha that is not a full 40-character commit id, or
that the repository does not know, is reported as a separate input error
before any lane is evaluated.

Exit status: 0 the release may proceed, 1 the release is refused,
2 the gate, the manifest, or the arguments given to the gate are unusable.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

EXIT_ALLOWED = 0
EXIT_REFUSED = 1
EXIT_MISCONFIGURED = 2

GATE_JOB = "release-gate"
GATE_WORKFLOW_REF = "uses: ./.github/workflows/release-gate.yml"


class GateError(Exception):
    """A refusal or a configuration error; carries the exit status."""

    def __init__(self, message: str, status: int = EXIT_REFUSED) -> None:
        super().__init__(message)
        self.status = status


def refuse(message: str) -> None:
    raise GateError(message, EXIT_REFUSED)


def misconfigured(message: str) -> None:
    raise GateError(message, EXIT_MISCONFIGURED)


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        misconfigured(f"missing file: {path}")


def read_json(path: Path):
    try:
        return json.loads(read_text(path))
    except json.JSONDecodeError as error:
        misconfigured(f"{path} is not valid JSON: {error}")


def load_manifest(root: Path) -> dict:
    manifest = read_json(root / "release-manifest.json")
    if manifest.get("schema") != 1:
        misconfigured("release-manifest.json must declare schema 1")
    release = manifest.get("release") or {}
    for key in ("entrypoint", "tagPattern", "gate", "requiredLanes", "versionSource"):
        if key not in release:
            misconfigured(f"release-manifest.json release.{key} is missing")
    if not manifest.get("units"):
        misconfigured("release-manifest.json declares no release units")
    return manifest


def strip_line_comments(text: str) -> str:
    return re.sub(r"(?m)^[ \t]*//.*$", "", text)


def boring_packages(root: Path) -> set[str]:
    document = json.loads(strip_line_comments(read_text(root / "boring.json")))
    names = {
        bundle["package"]["name"]
        for bundle in document.get("bundles", [])
        if bundle.get("package", {}).get("name")
    }
    if not names:
        misconfigured("boring.json declares no packaged bundle")
    return names


def npm_package(root: Path, relative: str) -> dict:
    document = read_json(root / relative)
    if not document.get("name"):
        misconfigured(f"{relative} declares no package name")
    return document


def gradle_module_artifacts(root: Path) -> set[str]:
    text = read_text(root / "build.gradle.kts")
    match = re.search(r"val publishedModules = mapOf\(", text)
    if not match:
        misconfigured("build.gradle.kts declares no publishedModules map")
    tail = text[match.end():]
    return set(re.findall(r"PublishedModule\(\s*\"([^\"]+)\"", tail))


def workspace_packages(root: Path) -> list[dict]:
    root_manifest = read_json(root / "package.json")
    packages: list[dict] = []
    for relative in root_manifest.get("workspaces", []):
        directory = root / relative
        manifest_path = directory / "package.json"
        if not manifest_path.exists():
            continue
        manifest = read_json(manifest_path)
        name = manifest.get("name")
        if not name:
            continue
        packages.append(
            {
                "name": name,
                "file": str((Path(relative) / "package.json").as_posix()),
                "private": bool(manifest.get("private", False)),
            }
        )
    return packages


def unit_packages(root: Path, unit: dict) -> set[str]:
    source = unit.get("packageSource") or {}
    kind = source.get("kind")
    files = source.get("files") or []
    if kind == "boring":
        return boring_packages(root)
    if kind == "npm":
        return {npm_package(root, relative)["name"] for relative in files}
    if kind == "gradle":
        return gradle_module_artifacts(root)
    misconfigured(f"unit {unit.get('id')} has an unknown packageSource kind {kind!r}")


def derived_unit(unit: dict) -> bool:
    """True when the unit derives its package list instead of declaring one."""
    return (unit.get("packageSource") or {}).get("kind") == "boring"


def matrix_packages(root: Path) -> set[str]:
    """The packages tools/release-matrix.py marks packed for the registry.

    The registry unit declares no package list: the gate compares the packages
    boring.json declares with the set the release matrix packs, so a bundle
    that drops out of the pack set fails the gate instead of shrinking the
    registry silently.
    """
    script = root / "tools" / "release-matrix.py"
    if not script.is_file():
        misconfigured(f"missing file: {script}")
    try:
        completed = subprocess.run(
            [sys.executable, str(script), "--json"],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as error:
        misconfigured(f"{script} --json failed: {error.stderr.strip() or error}")
    try:
        document = json.loads(completed.stdout)
    except json.JSONDecodeError as error:
        misconfigured(f"{script} --json is not valid JSON: {error}")
    return {
        entry["package"]
        for entry in document.get("bundles", [])
        if entry.get("packed") and entry.get("package")
    }


def check_manifest_units(manifest: dict) -> None:
    seen_packages: dict[str, str] = {}
    seen_ids: set[str] = set()
    ids = {unit["id"] for unit in manifest["units"]}
    for unit in manifest["units"]:
        unit_id = unit.get("id")
        if not unit_id or unit_id in seen_ids:
            misconfigured(f"duplicate or missing release unit id: {unit_id!r}")
        seen_ids.add(unit_id)
        for dependency in unit.get("dependsOn", []):
            if dependency not in ids:
                misconfigured(f"unit {unit_id} depends on unknown unit {dependency}")
        if derived_unit(unit) and not unit.get("packagesFrom"):
            misconfigured(f"unit {unit_id} derives its packages and must state packagesFrom")
        if not unit.get("workflow") or (not unit.get("packages") and not derived_unit(unit)):
            misconfigured(f"unit {unit_id} needs a workflow and a package list")
        for package in unit.get("packages", []):
            owner = seen_packages.get(package)
            if owner is not None:
                misconfigured(f"package {package} is released by both {owner} and {unit_id}")
            seen_packages[package] = unit_id

    # Dependency cycles would make the release order unsatisfiable.
    visiting: set[str] = set()
    ordered: set[str] = set()

    def visit(unit_id: str) -> None:
        if unit_id in ordered:
            return
        if unit_id in visiting:
            misconfigured(f"release unit dependency cycle at {unit_id}")
        visiting.add(unit_id)
        unit = next(item for item in manifest["units"] if item["id"] == unit_id)
        for dependency in unit.get("dependsOn", []):
            visit(dependency)
        visiting.remove(unit_id)
        ordered.add(unit_id)

    for unit_id in ids:
        visit(unit_id)


def check_coverage(root: Path, manifest: dict) -> list[str]:
    notes: list[str] = []
    release_packages: dict[str, str] = {}
    matrix = matrix_packages(root) if any(derived_unit(unit) for unit in manifest["units"]) else set()
    for unit in manifest["units"]:
        discovered = unit_packages(root, unit)
        if derived_unit(unit):
            if discovered != matrix:
                misconfigured(
                    f"unit {unit['id']} derives its packages from {unit.get('packagesFrom')}, but "
                    f"tools/release-matrix.py packs {sorted(matrix)} while boring.json declares {sorted(discovered)}"
                )
        else:
            declared = set(unit.get("packages", []))
            if declared != discovered:
                missing = sorted(discovered - declared)
                stale = sorted(declared - discovered)
                misconfigured(
                    f"unit {unit['id']} package list drifted: undeclared {missing}, declared-but-absent {stale}"
                )
        for package in discovered:
            release_packages[package] = unit["id"]

    workspace = workspace_packages(root)
    classified = {
        entry["package"]: entry for entry in manifest.get("notInRelease", [])
    }
    for item in workspace:
        name = item["name"]
        if name in release_packages:
            continue
        entry = classified.get(name)
        if entry is None:
            misconfigured(
                f"workspace package {name} ({item['file']}) is neither a release unit package nor declared under notInRelease"
            )
        if entry.get("file") != item["file"]:
            misconfigured(
                f"notInRelease entry for {name} points at {entry.get('file')}, workspace declares {item['file']}"
            )
        if not entry.get("reason"):
            misconfigured(f"notInRelease entry for {name} has no reason")
        if item["private"]:
            if "private" not in entry["reason"]:
                misconfigured(
                    f"{name} is private; its notInRelease reason must state that npm publish refuses it"
                )
        else:
            if "snapshot" not in entry["reason"]:
                misconfigured(
                    f"{name} is public; its notInRelease reason must state which snapshot lane publishes it"
                )
            for workflow in sorted((root / ".github/workflows").glob("*.yml")):
                if workflow.name == "snapshot-precompute.yml":
                    continue
                if name in workflow.read_text(encoding="utf-8"):
                    misconfigured(
                        f"{name} is declared snapshot-only but {workflow.name} references it"
                    )
        notes.append(f"{name}: not in the version release ({entry['reason']})")

    for name, entry in classified.items():
        if name not in {item["name"] for item in workspace}:
            misconfigured(f"notInRelease package {name} is not a workspace package")
    return notes


def job_needs(workflow_text: str) -> dict[str, list[str]]:
    """Map every job id in a workflow to its needs list (top-level jobs only)."""
    match = re.search(r"(?m)^jobs:\s*$", workflow_text)
    if not match:
        return {}
    jobs: dict[str, list[str]] = {}
    current: str | None = None
    for line in workflow_text[match.end():].splitlines():
        job = re.match(r"^  ([A-Za-z0-9_-]+):\s*$", line)
        if job:
            current = job.group(1)
            jobs[current] = []
            continue
        if current is not None:
            needs = re.match(r"^    needs:\s*\[(.*?)\]", line)
            if needs:
                jobs[current] = [item.strip() for item in needs.group(1).split(",") if item.strip()]
                continue
            scalar = re.match(r"^    needs:\s*([A-Za-z0-9_-]+)\s*$", line)
            if scalar:
                jobs[current] = [scalar.group(1)]
    return jobs


def check_static(root: Path, manifest: dict) -> list[str]:
    release = manifest["release"]
    entrypoint = root / release["entrypoint"]
    entry_text = read_text(entrypoint)
    if release["tagPattern"] not in entry_text:
        misconfigured(f"{release['entrypoint']} does not trigger on {release['tagPattern']}")

    gate_text = read_text(root / release["gate"])
    if "workflow_call:" not in gate_text:
        misconfigured(f"{release['gate']} is not a reusable workflow")

    for unit in manifest["units"]:
        relative = unit["workflow"]
        text = read_text(root / relative)
        if "workflow_call:" not in text:
            misconfigured(f"{relative} is not callable from the release entrypoint (no workflow_call)")
        if f"{GATE_JOB}:" not in text or GATE_WORKFLOW_REF not in text:
            misconfigured(f"{relative} does not run {GATE_JOB} before publishing")
        if re.search(r"@tiqian/[A-Za-z0-9._-]+@\*", text):
            misconfigured(f"{relative} still has its own package tag trigger; the release entrypoint is the only trigger")
        workflow_jobs = job_needs(text)
        gated = {GATE_JOB}
        changed = True
        while changed:
            changed = False
            for job, needs in workflow_jobs.items():
                if job in gated or not needs:
                    continue
                if all(need in gated for need in needs):
                    gated.add(job)
                    changed = True
        escaping = sorted(set(workflow_jobs) - gated)
        if escaping:
            misconfigured(f"{relative} has jobs that can publish without waiting for {GATE_JOB}: {escaping}")
        call = f"uses: ./{relative}"
        if call not in entry_text:
            misconfigured(f"{release['entrypoint']} does not call {relative}")
        call_block = entry_text[entry_text.index(call):][:400]
        if "secrets: inherit" not in call_block:
            misconfigured(
                f"{release['entrypoint']} calls {relative} without secrets: inherit; "
                "the called lane would lose NPM_DIST_TAG_TOKEN and the registry token"
            )

    entry_jobs = job_needs(entry_text)
    unit_ids = {unit["id"] for unit in manifest["units"]}
    for unit in manifest["units"]:
        unit_id = unit["id"]
        if unit_id not in entry_jobs:
            misconfigured(f"{release['entrypoint']} has no job named {unit_id}")
        needs = set(entry_jobs[unit_id])
        if "gate" not in needs:
            misconfigured(f"{release['entrypoint']} job {unit_id} does not depend on the gate")
        missing = set(unit.get("dependsOn", [])) - needs
        if missing:
            misconfigured(f"{release['entrypoint']} job {unit_id} does not depend on {sorted(missing)}")
    last = next((unit for unit in manifest["units"] if unit.get("last")), None)
    if last is None:
        misconfigured("release-manifest.json must mark the final unit with last: true")
    unmet = unit_ids - {last["id"]} - set(entry_jobs[last["id"]])
    if unmet:
        misconfigured(
            f"final unit {last['id']} does not depend on every other unit; a red {sorted(unmet)} would not block it"
        )

    for lane in release["requiredLanes"]:
        read_text(root / lane["workflow"])
    return [f"entrypoint {release['entrypoint']} triggers on {release['tagPattern']}"]


def api_headers(token: str | None) -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "tiqian-release-gate",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def api_json(url: str, token: str | None) -> object:
    request = urllib.request.Request(url, headers=api_headers(token))
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        misconfigured(f"GitHub API {url} returned HTTP {error.code}")
    except urllib.error.URLError as error:
        misconfigured(f"GitHub API {url} is unreachable: {error.reason}")
    return None


FULL_SHA = re.compile(r"[0-9a-fA-F]{40}")


def require_full_sha(sha: str) -> str:
    """Reject anything but a full commit id.

    GitHub records a workflow run's head_sha as the full 40-character id, so a
    short sha never compares equal to a run and would be reported as a lane
    that never ran.
    """
    if not FULL_SHA.fullmatch(sha):
        misconfigured(
            f"--sha {sha!r} is not a full 40-character hexadecimal commit id; "
            "the gate needs the complete commit sha, and a run records its head_sha as the full id"
        )
    return sha.lower()


def commit_exists(repo: str, sha: str, token: str | None) -> bool:
    """True when the repository knows the commit; a 404 answers no, it is not an API failure."""
    url = f"https://api.github.com/repos/{repo}/commits/{sha}"
    request = urllib.request.Request(url, headers=api_headers(token))
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            response.read()
        return True
    except urllib.error.HTTPError as error:
        # GitHub answers 404 for an unknown repository and 422 "No commit found
        # for SHA" for a commit the repository does not contain; both mean the
        # caller named a commit the gate cannot evaluate.
        if error.code in (404, 422):
            return False
        misconfigured(f"GitHub API {url} returned HTTP {error.code}")
    except urllib.error.URLError as error:
        misconfigured(f"GitHub API {url} is unreachable: {error.reason}")
    return False


def latest_run_for_lane(runs: list[dict], lane_file: str) -> dict | None:
    candidates = [run for run in runs if run.get("path") == lane_file]
    if not candidates:
        return None
    return max(candidates, key=lambda run: run.get("created_at", ""))


def fetch_lane_run(repo: str, sha: str, lane_file: str, token: str | None) -> dict | None:
    url = (
        f"https://api.github.com/repos/{repo}/actions/workflows/"
        f"{Path(lane_file).name}/runs?head_sha={sha}&per_page=100"
    )
    payload = api_json(url, token)
    runs = payload.get("workflow_runs", []) if isinstance(payload, dict) else []
    runs = [run for run in runs if run.get("head_sha") == sha and run.get("event", "push") in ("push", "workflow_dispatch")]
    return latest_run_for_lane(runs, lane_file)


def runs_from_fixture(path: Path, sha: str) -> list[dict]:
    payload = read_json(path)
    if isinstance(payload, dict) and "workflow_runs" in payload:
        return [
            run
            for run in payload["workflow_runs"]
            if run.get("head_sha") == sha and run.get("event", "push") in ("push", "workflow_dispatch")
        ]
    if isinstance(payload, dict) and "workflows" in payload:
        runs = []
        for lane_file, record in payload["workflows"].items():
            entry = dict(record)
            entry["path"] = lane_file
            entry.setdefault("head_sha", sha)
            runs.append(entry)
        return runs
    if isinstance(payload, list):
        return [run for run in payload if run.get("head_sha", sha) == sha]
    misconfigured(f"{path} is not a runs list or a workflows mapping")


def check_lanes(repo: str, sha: str, manifest: dict, token: str | None, fixture: Path | None) -> list[str]:
    release = manifest["release"]
    fixture_runs = runs_from_fixture(fixture, sha) if fixture else None
    lines: list[str] = []
    for lane in release["requiredLanes"]:
        lane_file = lane["workflow"]
        if fixture_runs is None:
            run = fetch_lane_run(repo, sha, lane_file, token)
        else:
            run = latest_run_for_lane(fixture_runs, lane_file)
        label = f"{lane['name']} ({Path(lane_file).name})"
        if run is None:
            refuse(
                f"{label} has no run recorded on {sha}; a missing run is not green "
                "(a run's head_sha is the full 40-character commit id)"
            )
        status = run.get("status")
        conclusion = run.get("conclusion")
        if status != "completed":
            refuse(f"{label} is {status} on {sha}; the release waits for a completed run")
        if conclusion != "success":
            refuse(f"{label} is {conclusion} on {sha}; every required lane must be green")
        lines.append(f"{label}: success on {sha}")
    return lines


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Decide whether a tiqian release may proceed.")
    parser.add_argument("--repo", help="owner/repository, for example tiqian-cjk/tiqian")
    parser.add_argument(
        "--sha",
        help="the release commit the lanes must have run on, as the full 40-character commit id",
    )
    parser.add_argument("--token", help="GitHub token with actions:read; unauthenticated reads work for public repositories")
    parser.add_argument("--runs-json", type=Path, help="read lane runs from a JSON fixture instead of the GitHub API (drills)")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent, help="repository root")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    root = args.root.resolve()
    try:
        # The commit id decides what the lane lookups mean, so reject an
        # unusable one before reading the manifest or calling the API.
        if not args.sha:
            misconfigured("--sha is required to evaluate lane runs")
        sha = require_full_sha(args.sha)
        if not args.runs_json and not args.repo:
            misconfigured("--repo is required when --runs-json is absent")
        if not args.runs_json and not commit_exists(args.repo, sha, args.token):
            misconfigured(
                f"commit {sha} does not exist in {args.repo}; "
                "an unknown commit is not the same as a commit whose lanes have no run"
            )
        manifest = load_manifest(root)
        structural = check_static(root, manifest) + check_coverage(root, manifest)
        for line in structural:
            print(f"GATE: {line}")
        print(f"GATE: evaluating {len(manifest['release']['requiredLanes'])} required lanes on {sha}")
        lane_lines = check_lanes(args.repo or "", sha, manifest, args.token, args.runs_json)
        for line in lane_lines:
            print(f"GATE: {line}")
    except GateError as error:
        print(f"GATE: {'MISCONFIGURED' if error.status == EXIT_MISCONFIGURED else 'REFUSE'}: {error}")
        return error.status
    print("GATE: PASS: every required lane is green on the release commit")
    return EXIT_ALLOWED


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
