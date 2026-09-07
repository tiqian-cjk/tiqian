#!/usr/bin/env python3
"""Install the repository git hooks from tools/git-hooks/ into the git
hooks directory. Run once after cloning:

    python3 tools/git-hooks/install.py

An existing hook file with different content moves aside once, to
<name>.before-tiqian, and the repository hook takes its place. Running
the installer again is safe and restores the same hooks.
"""
from __future__ import annotations

import shutil
import stat
import subprocess
from pathlib import Path

HOOK_NAMES = ("pre-commit",)


def hooks_dir(repo_root: Path) -> Path:
    # Linked worktrees read hooks from the main repository's common dir,
    # so install there regardless of which checkout runs the installer.
    out = subprocess.run(
        [
            "git",
            "-C",
            str(repo_root),
            "rev-parse",
            "--path-format=absolute",
            "--git-common-dir",
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    return Path(out) / "hooks"


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    source_dir = repo_root / "tools" / "git-hooks"
    target_dir = hooks_dir(repo_root)
    target_dir.mkdir(parents=True, exist_ok=True)
    for name in HOOK_NAMES:
        source = source_dir / name
        target = target_dir / name
        desired = source.read_text(encoding="utf-8")
        if target.exists() and target.read_text(encoding="utf-8") != desired:
            backup = target_dir / f"{name}.before-tiqian"
            if backup.exists():
                backup.unlink()
            shutil.move(str(target), str(backup))
            print(f"moved existing {name} to {backup.name}")
        target.write_text(desired, encoding="utf-8")
        mode = target.stat().st_mode
        target.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        print(f"installed {name} -> {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
