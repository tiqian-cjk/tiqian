#!/usr/bin/env python3
"""Combine disjoint release pack shards, rejecting conflicting files."""

import argparse
import filecmp
from pathlib import Path
import shutil


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("shards", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("shard_names", nargs="+")
    args = parser.parse_args()

    # Registry package README files may be shared across ecosystems.
    for name in args.shard_names:
        shard = args.shards / f"release-pack-{name}"
        for directory in ("registry-tree", "release-artifacts"):
            source = shard / directory
            if not source.is_dir():
                parser.error(f"missing {source}")
            for file in source.rglob("*"):
                if not file.is_file():
                    continue
                target = args.output / directory / file.relative_to(source)
                if target.exists():
                    if not filecmp.cmp(file, target, shallow=False):
                        parser.error(f"conflicting release output {target} from {shard.name}")
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(file, target)


if __name__ == "__main__":
    main()
