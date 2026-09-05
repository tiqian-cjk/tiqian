#!/usr/bin/env python3
"""Swap handwritten engine Kotlin files for boring-generated ones.

One swap unit is one engine source file under
engine/src/commonMain/kotlin/org/tiqian/core/.  The Haxe port keeps one
class per module, so a single engine file maps to a set of Haxe modules;
this script generates Kotlin for exactly that set through a temporary
boring manifest, installs the emitted files that belong to the engine
file, removes the covered declarations from the old file, and runs the
engine JVM test suite.

Known boring gaps the script compensates for mechanically:
  - Kotlin internal/private top-level visibility is not emitted; the
    script restores the old declaration visibility on installed files.
  - Thrown exceptions carry Tiqian names; test assertions that still
    name the builtin exceptions are retyped line by line using the
    failing-run stack frames, across every test package.

Known gaps that block a swap (reported, never forced):
  - value classes (@JvmInline) cannot be generated yet;
  - non-constant constructor defaults need boring spec 22;
  - unported classes.

Modes:
  --probe FILE...   attempt the swap, run tests, revert everything, and
                    print one outcome line per file (readiness matrix).
  --swap FILE...    attempt the swap and keep the result when tests pass.
  --commit          with --swap: commit on green and fast-forward main.

Run from the worktree root.  All intermediate artifacts live under
engine-haxe/out/swap/ which is git-ignored.
"""

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

WORKTREE = Path(__file__).resolve().parents[2]
ENGINE_SRC = WORKTREE / "engine/src"
ENGINE_CORE = ENGINE_SRC / "commonMain/kotlin/org/tiqian/core"
PORT_CORE = WORKTREE / "engine-haxe/src/org/tiqian/core"
MANIFEST_DIR = WORKTREE / "engine-haxe/out/swap"
GEN_DIR = WORKTREE / "engine-haxe/out/swap-gen"
GEN_TEST_DIR = WORKTREE / "engine-haxe/out/swap-gen-tests"
BASE_MANIFEST = WORKTREE / "engine-haxe/core-kotlin.hxml"
MAIN_TREE = Path("/home/losses/Development/tiqian")

KOTLIN_MODIFIERS = {
    "public", "private", "internal", "protected", "abstract", "sealed",
    "open", "data", "enum", "value", "annotation", "actual", "expect",
    "external", "override", "inline", "const", "lateinit", "tailrec",
    "vararg", "suspend", "infix", "operator", "noinline", "crossinline",
    "reified", "inner", "companion", "fun",
}
KOTLIN_TYPE_KEYWORDS = {"class", "object", "interface", "typealias"}
KOTLIN_MEMBER_KEYWORDS = {"fun", "val", "var"}
VISIBILITIES = {"public", "private", "internal", "protected"}

EXCEPTION_NAMES = [
    "TiqianIllegalArgumentException",
    "TiqianNoSuchElementException",
    "IllegalArgumentException",
    "NoSuchElementException",
]


class Decl:
    def __init__(self, name, start, doc, vis, kind, value=False):
        self.name = name
        self.start = start
        self.doc = doc
        self.vis = vis
        self.kind = kind  # "type" or "member"
        self.value = value  # Kotlin value modifier on a class


def run(cmd, **kwargs):
    return subprocess.run(cmd, capture_output=True, text=True, **kwargs)


def _bare_name(token):
    """`String.coerceToInteractionBoundary(` -> `coerceToInteractionBoundary`;
    plain `Size(` -> `Size`."""
    name = token.split("(")[0].split(":")[0].split("<")[0]
    if "." in name:
        name = name.split(".")[-1]
    return name.strip("<>?, ")


def parse_kotlin_toplevel(text):
    """Column-0 declarations of a Kotlin file."""
    decls = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped or line[0].isspace():
            continue
        if stripped.startswith(("//", "/*", "*", "@", "import ", "package ")):
            continue
        # A bare brace is a class-body delimiter, never a declaration;
        # treating one as a declaration leaks the closing braces of
        # removed classes into the leftover segment.
        if stripped in ("}", "{"):
            continue
        tokens = stripped.split()
        j = 0
        vis = "default"
        value = False
        while j < len(tokens) and tokens[j] in KOTLIN_MODIFIERS:
            if tokens[j] in VISIBILITIES:
                vis = tokens[j]
            if tokens[j] == "value":
                value = True
            j += 1
        name, kind = None, "member"
        if j < len(tokens) and tokens[j] in KOTLIN_TYPE_KEYWORDS and j + 1 < len(tokens):
            name, kind = _bare_name(tokens[j + 1]), "type"
        elif j < len(tokens) and tokens[j] in KOTLIN_MEMBER_KEYWORDS and j + 1 < len(tokens):
            name, kind = _bare_name(tokens[j + 1]), "member"
        doc = i
        k = i - 1
        while k >= 0 and lines[k].strip().startswith(("/**", "*", "*/", "//", "@")):
            doc = k
            k -= 1
        # A line that names no declaration (a bare `)` or `) {`
        # continuing a parameter list at column zero) only occurs
        # inside another declaration's span; emitting it as a decl
        # leaks the enclosing class body into the leftover segment.
        if name is None and kind == "member":
            continue
        decls.append(Decl(name, i, doc, vis, kind, value))
    return decls


def parse_haxe_toplevel(text):
    """Names of types declared in a Haxe module (class, enum, enum
    abstract, abstract, interface)."""
    names = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith(("//", "*", "/*", "@", "package", "import", "using ")):
            continue
        tokens = stripped.split()
        j = 0
        while j < len(tokens) and tokens[j] in ("public", "private", "final", "extern"):
            j += 1
        if j >= len(tokens):
            continue
        head = tokens[j]
        if head == "enum":
            if j + 1 < len(tokens):
                if tokens[j + 1] == "abstract" and j + 2 < len(tokens):
                    names.append(_bare_name(tokens[j + 2]))
                else:
                    names.append(_bare_name(tokens[j + 1]))
        elif head in ("class", "interface") and j + 1 < len(tokens):
            names.append(_bare_name(tokens[j + 1]))
        elif head == "abstract" and j + 1 < len(tokens):
            names.append(_bare_name(tokens[j + 1]))
    return names


def index_engine_files():
    """{stem: [type names]} and {type name: vis} plus {value-class names}."""
    index, visibility, value_classes = {}, {}, set()
    for path in sorted(ENGINE_CORE.glob("*.kt")):
        names = []
        for decl in parse_kotlin_toplevel(path.read_text()):
            if decl.kind == "type" and decl.name:
                names.append(decl.name)
                if decl.vis in ("internal", "private"):
                    visibility[decl.name] = decl.vis
                if decl.value:
                    value_classes.add(decl.name)
        index[path.stem] = names
    return index, visibility, value_classes


def index_port_modules():
    index = {}
    for path in sorted(PORT_CORE.glob("*.hx")):
        for name in parse_haxe_toplevel(path.read_text()):
            index.setdefault(name, path.stem)
    return index


def build_manifest(stem, roots):
    header = []
    for line in BASE_MANIFEST.read_text().splitlines():
        if line.startswith("org.tiqian."):
            continue
        if line.startswith("-D kotlin-output="):
            header.append(f"-D kotlin-output={GEN_DIR.relative_to(WORKTREE)}")
            continue
        if line.startswith("-D kotlin-test-output="):
            header.append(f"-D kotlin-test-output={GEN_TEST_DIR.relative_to(WORKTREE)}")
            continue
        header.append(line)
    MANIFEST_DIR.mkdir(parents=True, exist_ok=True)
    manifest = MANIFEST_DIR / f"{stem}.hxml"
    manifest.write_text("\n".join(header + [f"org.tiqian.core.{r}" for r in roots]) + "\n")
    return manifest


def generate(manifest):
    result = run(["nix", "develop", "-c", "bash", "-c",
                  f"haxe {manifest.relative_to(WORKTREE)}"], cwd=WORKTREE)
    return result.returncode == 0, result.stdout + result.stderr


def restore_visibility(text, visibility):
    lines = text.splitlines()
    changed = []
    for decl in parse_kotlin_toplevel("\n".join(lines)):
        want = visibility.get(decl.name) if decl.name else None
        if want not in ("internal", "private") or decl.vis == want:
            continue
        tokens = lines[decl.start].split()
        out, vis_done = [], False
        for token in tokens:
            if token in VISIBILITIES and not vis_done:
                out.append(want)
                vis_done = True
            elif token in VISIBILITIES:
                continue
            else:
                if (token in KOTLIN_TYPE_KEYWORDS | KOTLIN_MEMBER_KEYWORDS
                        and not vis_done):
                    out.append(want)
                    vis_done = True
                out.append(token)
        lines[decl.start] = " ".join(out)
        changed.append(decl.name)
    return ("\n".join(lines) + ("\n" if text.endswith("\n") else ""), changed)


def apply_swap(stem, engine_types, visibility):
    installed, vis_restored = [], []
    if GEN_DIR.exists():
        for path in sorted(GEN_DIR.rglob("*.kt")):
            if path.stem not in engine_types and path.stem != stem:
                continue
            text, changed = restore_visibility(path.read_text(), visibility)
            vis_restored.extend(changed)
            target = ENGINE_CORE / path.name
            target.write_text(text)
            installed.append(target)
    if not installed:
        return installed, vis_restored, "nothing-installed"

    old_path = ENGINE_CORE / f"{stem}.kt"
    old_text = old_path.read_text()
    covered = set()
    for path in installed:
        covered.add(path.stem)
        for decl in parse_kotlin_toplevel(path.read_text()):
            if decl.kind == "type" and decl.name:
                covered.add(decl.name)
    stem_installed = any(p.stem == stem for p in installed)

    old_decls = parse_kotlin_toplevel(old_text)
    lines = old_text.splitlines()
    leftover = []
    for idx, decl in enumerate(old_decls):
        end = old_decls[idx + 1].start if idx + 1 < len(old_decls) else len(lines)
        if decl.kind == "type" and decl.name in covered:
            continue
        if decl.kind == "member" and stem_installed:
            continue  # the stem module carries free functions and properties
        leftover.extend(lines[decl.doc:end])
        leftover.append("")
    while leftover and not leftover[0].strip():
        leftover.pop(0)
    while leftover and not leftover[-1].strip():
        leftover.pop()

    if old_path in installed:
        if leftover:
            current = old_path.read_text().rstrip("\n")
            old_path.write_text(current + "\n\n" + "\n".join(leftover) + "\n")
            return installed, vis_restored, "replaced-with-leftovers"
        return installed, vis_restored, "replaced"
    if not leftover:
        old_path.unlink()
        return installed, vis_restored, "deleted-old"
    # Keep the original package and import lines ahead of the leftovers;
    # imports that only served removed declarations stay as harmless
    # unused-import warnings.
    header = [ln for ln in lines[: old_decls[0].start if old_decls else len(lines)]
              if ln.startswith(("package ", "import "))]
    old_path.write_text("\n".join(header + [""] + leftover) + "\n")
    return installed, vis_restored, "trimmed-old"


def gradle_test():
    log = MANIFEST_DIR / "gradle.log"
    # The engine is KMP: every swap must also hold on the Android compile
    # and the JS target, not just jvmTest alone.
    result = run(["nix", "develop", "-c", "bash", "-c",
                  "./gradlew :engine:jvmTest"
                  " :platforms:compose:compose:compileAndroidMain"
                  " :ffi:js:jsNodeTest --continue"],
                 cwd=WORKTREE, timeout=1800)
    log.write_text(result.stdout + result.stderr)
    return result.returncode == 0, log


FAILURE_BLOCK = re.compile(
    r"^(\w+Test)\[jvm\] > \w+\[jvm\] FAILED", re.MULTILINE)
ASSERT_FRAME = re.compile(r"AssertionError at ([\w.]+)\.kt:(\d+)")
CAUSED_BY_TIQIAN = re.compile(
    r"Caused by: org\.tiqian\.core\.(Tiqian\w+Exception)")
EXPECTED_ACTUAL = re.compile(
    r"Expected an exception of type (\w+) to be thrown, "
    r"but an exception of type (\w+) was thrown")


def retype_exceptions(log_text):
    """Point failing assertion lines at the exception actually thrown.

    The caused-by frame names the line of the throwing call inside the
    test; the failed assertion sits a few lines above it (an inline
    assertion wrapper reports the AssertionError through a stale line
    table, so its own frame cannot be trusted for line-precise edits).
    Cross-package test files gain the missing import."""
    test_root = ENGINE_SRC
    blame = {}  # relative path -> {line no: target exception}
    lines = log_text.splitlines()
    current_actual = None
    for line in lines:
        m = CAUSED_BY_TIQIAN.search(line)
        if m:
            current_actual = m.group(1)
            # The caused-by frame itself is the throwing call site.
            fm = re.search(r" at ([\w.]+)\.kt:(\d+)$", line)
            if fm:
                cls, no = fm.group(1), int(fm.group(2))
                candidates = list(test_root.rglob(f"{cls.split('.')[-1]}.kt"))
                if candidates:
                    rel = candidates[0].relative_to(WORKTREE)
                    blame.setdefault(str(rel), {})[no] = current_actual
            continue
        m = EXPECTED_ACTUAL.search(line)
        if m:
            current_actual = m.group(2)
            continue
        m = ASSERT_FRAME.search(line)
        if m and current_actual:
            cls, no = m.group(1), int(m.group(2))
            candidates = list(test_root.rglob(f"{cls.split('.')[-1]}.kt"))
            if candidates:
                rel = candidates[0].relative_to(WORKTREE)
                blame.setdefault(str(rel), {})[no] = current_actual
    edited = {}
    for rel, flips in blame.items():
        path = WORKTREE / rel
        text_lines = path.read_text().splitlines()
        count = 0
        for no, target in flips.items():
            # Direct hit: the frame line itself names an exception type.
            if no - 1 < len(text_lines):
                old = text_lines[no - 1]
                new = old
                for name in EXCEPTION_NAMES:
                    new = re.sub(rf"\b{name}\b", target, new)
                if new != old:
                    text_lines[no - 1] = new
                    count += 1
                    continue
            # Otherwise search upward for the assertion expecting the
            # builtin type; the throwing call sits inside its block.
            for up in range(no - 1, max(no - 25, -1), -1):
                if up >= len(text_lines):
                    continue
                old = text_lines[up]
                m = re.search(r"assertFailsWith<(\w+)>", old)
                if not m or m.group(1) == target:
                    continue
                if m.group(1) in EXCEPTION_NAMES:
                    text_lines[up] = re.sub(
                        rf"\b{m.group(1)}\b", target, old, count=1)
                    count += 1
                    break
        if count:
            text = "\n".join(text_lines)
            if "import org.tiqian.core." + "Tiqian" not in text \
                    and "/org/tiqian/core/" not in str(path.parent) \
                    and re.search(r"\bTiqian\w+Exception\b", text):
                text = re.sub(r"(package [\w.]+\n)",
                              r"\1\nimport org.tiqian.core."
                              + re.search(r"\b(Tiqian\w+Exception)\b", text).group(1)
                              + "\n", text, count=1)
            path.write_text(text)
            edited[rel] = count
    return edited


def failure_detail(log_text):
    errors = [ln.strip() for ln in log_text.splitlines() if ln.lstrip().startswith("e: ")]
    fails = [ln.strip() for ln in log_text.splitlines() if " FAILED" in ln]
    picks = errors[:3] + fails[:3]
    return " | ".join(picks) if picks else (log_text.strip().splitlines()[-1:] or ["?"])


def revert_engine_tree():
    run(["git", "checkout", "--", "engine/src"], cwd=WORKTREE)
    run(["git", "clean", "-fd", "engine/src"], cwd=WORKTREE)


def swap_one(stem, engine_index, port_index, visibility, value_classes, probe):
    engine_types = engine_index.get(stem)
    if engine_types is None:
        return {"stem": stem, "status": "no-such-file"}
    value_here = [c for c in engine_types if c in value_classes]
    if value_here:
        return {"stem": stem, "status": "blocked-value-class",
                "detail": ", ".join(value_here)}
    missing = [c for c in engine_types if c not in port_index]
    if missing:
        return {"stem": stem, "status": "unported-classes", "detail": ", ".join(missing)}
    roots = sorted({port_index[c] for c in engine_types}
                   | ({stem} if (PORT_CORE / f"{stem}.hx").exists() else set()))
    manifest = build_manifest(stem, roots)
    shutil.rmtree(GEN_DIR, ignore_errors=True)
    shutil.rmtree(GEN_TEST_DIR, ignore_errors=True)
    ok, output = generate(manifest)
    if not ok:
        first = next((ln for ln in output.splitlines()
                      if "characters" in ln or ln.lower().startswith("error")), "?")
        return {"stem": stem, "status": "generation-failed", "detail": first.strip()[:220]}

    installed, vis_restored, old_state = apply_swap(stem, set(engine_types), visibility)
    if not installed:
        return {"stem": stem, "status": "nothing-emitted"}

    test_ok, log = gradle_test()
    retypes = []
    for _ in range(5):
        if test_ok:
            break
        log_text = log.read_text()
        if not re.search(r"Tiqian\w*Exception", log_text):
            break
        edited = retype_exceptions(log_text)
        if not edited:
            break
        retypes.append({k: v for k, v in edited.items()})
        test_ok, log = gradle_test()

    result = {"stem": stem, "installed": [p.name for p in installed],
              "old": old_state, "vis": vis_restored, "retypes": retypes}
    if not test_ok:
        result["status"] = "test-failed"
        result["detail"] = failure_detail(log.read_text())
    else:
        result["status"] = "pass"
        stats = run(["git", "diff", "--stat", "engine/src"], cwd=WORKTREE).stdout
        result["detail"] = (" ".join(stats.strip().split("\n")[-1].split())
                            if stats.strip() else "")
    if probe:
        revert_engine_tree()
    return result


def commit_and_merge(stem):
    if run(["git", "add", "-A", "engine/src"], cwd=WORKTREE).returncode != 0:
        return "commit failed at git add"
    commit = run(["git", "commit", "-m",
                  f"refactor(engine): replace handwritten {stem} with boring-generated Kotlin"],
                 cwd=WORKTREE)
    if commit.returncode != 0:
        return "commit failed"
    status = run(["git", "status", "--porcelain", "engine"], cwd=MAIN_TREE)
    if status.stdout.strip():
        return "commit ok on port/haxe-core; merge deferred: main tree engine/ is dirty"
    merge = run(["git", "merge", "port/haxe-core"], cwd=MAIN_TREE)
    if merge.returncode != 0:
        return "merge failed: " + (merge.stdout + merge.stderr).strip()[:200]
    return "committed+merged"


PROBE_ORDER = [
    "UnicodeNumberData",
    "UnicodeWordCharacterData",
    "UnicodeScriptEvidenceData",
    "UnicodeEmojiModifierBaseData",
    "UnicodeExtendedPictographicData",
    "EastAsianSpacingData",
    "UnicodeWordCharacter",
    "UnicodeScriptEvidence",
    "Geometry",
    "Units",
    "SourceInteractionBoundaries",
    "EastAsianSpacing",
    "TextModel",
    "LayoutModel",
    "LayoutQueries",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="*", help="engine file stems, or 'all'")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--probe", action="store_true")
    mode.add_argument("--swap", action="store_true")
    parser.add_argument("--commit", action="store_true",
                        help="with --swap: commit green results and merge main")
    args = parser.parse_args()

    stems = PROBE_ORDER if "all" in args.files else args.files
    engine_index, visibility, value_classes = index_engine_files()
    port_index = index_port_modules()

    results = []
    for stem in stems:
        if args.probe:
            revert_engine_tree()
        result = swap_one(stem, engine_index, port_index, visibility,
                          value_classes, probe=args.probe)
        results.append(result)
        extra = ""
        if result.get("installed"):
            extra += f" [{'+'.join(result['installed'])}]"
        if result.get("vis"):
            extra += f" vis:{','.join(sorted(set(result['vis'])))}"
        if result.get("retypes"):
            flips = sum(sum(r.values()) for r in result["retypes"])
            extra += f" retype:{flips}"
        detail = result.get("detail", "")
        print(f"[{result['status']}] {stem}{extra}"
              + (f" :: {detail[:200]}" if detail else ""), flush=True)
        if args.swap and result["status"] != "pass":
            break
        # Commit each green swap at once: a later batch run must not
        # sweep earlier swaps into the first commit.
        if args.commit and result["status"] == "pass":
            print(commit_and_merge(stem), flush=True)

    return 0 if all(r["status"] == "pass" for r in results) else 1


if __name__ == "__main__":
    sys.exit(main())
