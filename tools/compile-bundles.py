#!/usr/bin/env python3
"""Compile every bundle's generated tree with its target toolchain.

The pack action compiles two targets and archives the rest: a TypeScript
bundle goes through package-tsc, a Kotlin bundle through package-kotlinc or
the bundle's mavenPublication command, and the Swift zip, the Dart pub archive
and the Rust crate are archives of the generated sources
(packages/compiler/PackageArtifacts.hx in the pinned boring checkout). A
generation defect in those three targets therefore reaches the release without
any compiler having read the code.

This tool is the compile point for those targets. It runs after the pack stage,
one compiler invocation per bundle, and reports every bundle it did not compile
itself so no bundle can drop out of the check silently:

  swift   swiftc -emit-library -emit-module -O -wmo <gen>/*.swift
  dart    dart analyze --no-fatal-warnings <gen>   (only analyzer errors fail)
  rust    cargo build --release --manifest-path <gen>/Cargo.toml

TypeScript and Kotlin are compiled by boring pack itself; this tool records
that compile point instead of running the compiler a second time. A bundle
whose target is in neither table fails the run, so a new target cannot be added
without a compile point.

Usage:
    tools/compile-bundles.py [--project boring.json] [--bundles <id> ...]
                             [--list] [--dry-run]

Exit status: 0 every bundle compiled (or is compiled by pack), 1 a compile
failed or a bundle declares no compile point, 2 the project file is unusable.

Run inside the flake devShell (nix develop): the Swift toolchain and the boring
driver come from it, the same shell the release workflow uses.
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

EXIT_OK = 0
EXIT_FAILED = 1
EXIT_MISCONFIGURED = 2

# Targets whose generated sources boring pack compiles. The compile point is
# written out so a reader can check it against the pinned driver:
# PackageArtifacts.hx:184-209 (npm: tsc over the staged package) and
# PackageArtifacts.hx:357-384 (maven: kotlinc over the generated .kt files).
PACK_COMPILES = {
    "ts": "boring pack: package-tsc",
    "kotlin": "boring pack: package-kotlinc or mavenPublication",
}

# Targets this tool compiles. The command mirrors the build step of the
# driver's test lane (driver Plan.hx testSteps), minus running anything.
TOOL_COMPILES = {
    "swift": "swiftc -emit-library -emit-module",
    "dart": "dart analyze --no-fatal-warnings",
    "rust": "cargo build --release",
}


class Misconfigured(Exception):
    """The project file cannot produce a compile plan."""


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


def define_value(args: list, name: str):
    """The value of -D <name>=<value> in a haxe argument list, or None."""
    index = 0
    while index + 1 < len(args):
        if args[index] == "-D" and args[index + 1].startswith(name + "="):
            return args[index + 1].split("=", 1)[1]
        index += 1
    return None


def roots_file_define(roots: pathlib.Path, name: str, seen: list, project_root: pathlib.Path):
    """The value of -D <name>=<value> anywhere on a roots file include chain.

    The driver resolves the same value for the Swift module name (Main.hx
    rootsFileDefine): non-flag lines are includes resolved against the project
    root first and the including file's directory second, and a later define
    wins.
    """
    if not roots.is_file() or str(roots) in seen:
        return None
    seen.append(str(roots))
    found = None
    for raw in roots.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        tokens = line.split()
        if tokens[0] in ("-D", "--define") and len(tokens) > 1:
            if tokens[1].startswith(name + "="):
                found = tokens[1].split("=", 1)[1]
            elif tokens[1] == name and len(tokens) > 2:
                found = " ".join(tokens[2:])
            continue
        if len(tokens) == 1 and not tokens[0].startswith("-"):
            for base in (project_root, roots.parent):
                candidate = (base / tokens[0]).resolve()
                if candidate == roots or not candidate.is_file():
                    continue
                nested = roots_file_define(candidate, name, seen, project_root)
                if nested is not None:
                    found = nested
    return found


def swift_module(project_root: pathlib.Path, bundle: dict) -> str:
    module = define_value(bundle.get("haxeArgs") or [], "swift-test-import")
    if module:
        return module
    roots_file = bundle.get("rootsFile")
    if roots_file:
        module = roots_file_define(project_root / roots_file, "swift-test-import", [], project_root)
        if module:
            return module
    raise Misconfigured(
        'bundle "%s": the swift bundle names no module; put -D swift-test-import=<module> '
        "in its haxeArgs or on its roots file include chain" % bundle.get("id")
    )


def walk(dir_path: pathlib.Path, suffix: str) -> list:
    if not dir_path.is_dir():
        return []
    return sorted(str(path) for path in dir_path.rglob("*" + suffix) if path.is_file())


def build_env(bundle: dict) -> dict:
    env = os.environ.copy()
    build = bundle.get("build") or {}
    for entry in build.get("env") or []:
        key = entry.get("key")
        if key:
            env[key] = str(entry.get("value", ""))
    return env


def plan_command(project_root: pathlib.Path, out_root: pathlib.Path, bundle: dict) -> dict:
    """One compile plan: the compile point, the command, and the environment."""
    bundle_id = bundle["id"]
    target = bundle.get("target")
    if target in PACK_COMPILES:
        package = bundle.get("package") or {}
        if not package.get("name") or not package.get("version"):
            raise Misconfigured(
                'bundle "%s": target %s is compiled by boring pack, but the bundle declares no '
                "package name and version, so pack writes no artifact and runs no compiler"
                % (bundle_id, target)
            )
        return {"bundle": bundle_id, "target": target, "point": PACK_COMPILES[target], "skip": True}
    if target not in TOOL_COMPILES:
        raise Misconfigured(
            'bundle "%s": target "%s" has no declared compile point; add it to PACK_COMPILES '
            "(boring pack compiles it) or TOOL_COMPILES (this tool compiles it)" % (bundle_id, target)
        )
    gen = out_root / bundle_id / "gen"
    build = out_root / bundle_id / "build" / "compile"
    env = build_env(bundle)
    build_args = list((bundle.get("build") or {}).get("args") or [])
    if target == "swift":
        files = walk(gen, ".swift")
        if not files:
            raise Misconfigured('bundle "%s": no generated .swift files under %s; run boring gen first' % (bundle_id, gen))
        module = swift_module(project_root, bundle)
        build.mkdir(parents=True, exist_ok=True)
        output = build / ("lib" + module + (".dylib" if sys.platform == "darwin" else ".so"))
        import_args = []
        system_package = env.get("BORING_SWIFT_SYSTEM_PACKAGE", "")
        imports_system = any(
            "import SystemPackage" in pathlib.Path(path).read_text(encoding="utf-8", errors="replace")
            for path in files
        )
        if imports_system:
            if not system_package:
                raise Misconfigured(
                    'bundle "%s": the generated tree imports SystemPackage; point '
                    "BORING_SWIFT_SYSTEM_PACKAGE at the built module" % bundle_id
                )
            import_args = ["-I", system_package, "-L", system_package, "-lSystemPackage"]
        command = ["swiftc", "-emit-library", "-emit-module", "-O", "-wmo"] + import_args + files + build_args + [
            "-module-name", module, "-o", str(output)
        ]
        return {"bundle": bundle_id, "target": target, "point": TOOL_COMPILES[target], "command": command, "env": env, "skip": False}
    if target == "dart":
        if not (gen / "pubspec.yaml").is_file():
            raise Misconfigured('bundle "%s": no generated pubspec.yaml under %s; run boring gen first' % (bundle_id, gen))
        return {
            "bundle": bundle_id,
            "target": target,
            "point": TOOL_COMPILES[target],
            "command": ["dart", "analyze", "--no-fatal-warnings", "."],
            "cwd": str(gen),
            "env": env,
            "skip": False,
        }
    if target == "rust":
        manifest = gen / "Cargo.toml"
        if not manifest.is_file():
            raise Misconfigured('bundle "%s": no generated Cargo.toml under %s; run boring gen first' % (bundle_id, gen))
        env["CARGO_TARGET_DIR"] = str(build / "cargo-target")
        return {
            "bundle": bundle_id,
            "target": target,
            "point": TOOL_COMPILES[target],
            "command": ["cargo", "build", "--release", "--manifest-path", str(manifest)] + build_args,
            "env": env,
            "skip": False,
        }
    raise Misconfigured('bundle "%s": unreachable plan' % bundle_id)


def run(plan: dict) -> int:
    if plan["skip"]:
        print("  = %-14s %-6s %s (compiled by pack)" % (plan["bundle"], plan["target"], plan["point"]))
        return EXIT_OK
    command = plan["command"]
    print("  $ " + " ".join(command))
    result = subprocess.run(
        command,
        cwd=plan.get("cwd"),
        env=plan["env"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        errors="replace",
    )
    if plan["target"] == "dart":
        # dart analyze exits non-zero for warnings and for errors alike; a
        # warning is not a compile failure (the warning baseline is a separate
        # gate), so only analyzer errors count here.
        errors = [line for line in result.stdout.splitlines() if re.match(r"^\s*error\s+-\s", line)]
        if errors:
            print("  ! %-14s %d analyzer error(s)" % (plan["bundle"], len(errors)))
            for line in errors[:10]:
                print("    " + line.strip())
            return EXIT_FAILED
        print("  + %-14s analyzer errors 0 (warnings are not compile failures)" % plan["bundle"])
        return EXIT_OK
    if result.returncode != 0:
        print("  ! %-14s compiler exit code %d" % (plan["bundle"], result.returncode))
        for line in result.stdout.splitlines()[-20:]:
            print("    " + line)
        return EXIT_FAILED
    print("  + %-14s compiler exit code 0" % plan["bundle"])
    return EXIT_OK


def matrix(project: dict, out_root: pathlib.Path) -> list:
    rows = []
    for bundle in project.get("bundles") or []:
        if not bundle.get("id"):
            raise Misconfigured("%s has a bundle without an id" % project.get("path"))
        target = bundle.get("target")
        rows.append(
            {
                "bundle": bundle["id"],
                "target": target,
                "compile_point": PACK_COMPILES.get(target) or TOOL_COMPILES.get(target) or "none",
                "compiled_by": "pack" if target in PACK_COMPILES else ("compile-bundles" if target in TOOL_COMPILES else "none"),
                "gen": str(out_root / bundle["id"] / "gen"),
            }
        )
    return rows


def main(argv: list) -> int:
    parser = argparse.ArgumentParser(description="Compile every bundle's generated tree.")
    parser.add_argument("--project", type=pathlib.Path, default=pathlib.Path("boring.json"))
    parser.add_argument("--bundles", nargs="*", default=None, help="bundle ids to check (default: every bundle)")
    parser.add_argument("--list", action="store_true", help="print the compile matrix and exit")
    parser.add_argument("--dry-run", action="store_true", help="print every command without running it")
    args = parser.parse_args(argv)
    try:
        project = read_project(args.project)
    except Misconfigured as error:
        print("MISCONFIGURED: %s" % error)
        return EXIT_MISCONFIGURED
    project["path"] = str(args.project)
    project_root = args.project.resolve().parent
    out_root = project_root / project.get("outRoot", "engine-haxe/out")
    try:
        rows = matrix(project, out_root)
    except Misconfigured as error:
        print("MISCONFIGURED: %s" % error)
        return EXIT_MISCONFIGURED
    if args.list:
        print("%-16s %-7s %-40s %s" % ("bundle", "target", "compile point", "compiled by"))
        for row in rows:
            print("%-16s %-7s %-40s %s" % (row["bundle"], row["target"], row["compile_point"], row["compiled_by"]))
        return EXIT_OK
    bundles = project.get("bundles") or []
    if args.bundles:
        wanted = set(args.bundles)
        unknown = sorted(wanted - {bundle.get("id") for bundle in bundles})
        if unknown:
            print("MISCONFIGURED: unknown bundle id(s): %s" % ", ".join(unknown))
            return EXIT_MISCONFIGURED
        bundles = [bundle for bundle in bundles if bundle.get("id") in wanted]
    failures = 0
    for bundle in bundles:
        try:
            plan = plan_command(project_root, out_root, bundle)
        except Misconfigured as error:
            print("FAIL: %s" % error)
            failures += 1
            continue
        if args.dry_run:
            if plan["skip"]:
                print("  = %-14s %-6s %s (compiled by pack)" % (plan["bundle"], plan["target"], plan["point"]))
            else:
                print("  $ " + " ".join(plan["command"]))
            continue
        if not plan["skip"] and shutil.which(plan["command"][0]) is None:
            print('FAIL: bundle "%s" needs %s on PATH; run inside nix develop' % (plan["bundle"], plan["command"][0]))
            failures += 1
            continue
        failures += 1 if run(plan) != EXIT_OK else 0
    checked = len(bundles)
    compiled = len([bundle for bundle in bundles if bundle.get("target") in TOOL_COMPILES])
    by_pack = checked - compiled
    print()
    print("compile-bundles: %d bundle(s); %d compiled here, %d by boring pack, %d failure(s)" % (checked, compiled, by_pack, failures))
    return EXIT_FAILED if failures else EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
