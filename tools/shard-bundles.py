#!/usr/bin/env python3
"""Split a bundle list into balanced shards.

Each bundle costs a different amount of runner time, so a round-robin split
leaves one shard far behind the rest. This assigns the bundles longest-first to
the shard with the least load, which keeps the slowest shard close to the total
divided by the shard count.

The cost table lives in tools/shard-costs.json. A bundle missing from the table
gets the median cost, so a new bundle still lands somewhere sensible before its
measurement arrives.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

DEFAULT_COSTS = Path(__file__).with_name("shard-costs.json")
MAX_SHARDS = 13
MIN_SHARDS = 2


def load_costs(path: Path, phase: str, bundles: list[str]) -> dict[str, float]:
    table = json.loads(path.read_text())
    phase_costs = {str(key): float(value) for key, value in table.get(phase, {}).items()}
    known = sorted(phase_costs.values())
    if known:
        median = known[len(known) // 2]
    else:
        median = 300.0
    return {bundle: float(phase_costs.get(bundle, median)) for bundle in bundles}


def shard_count(total: float, target: float) -> int:
    if target <= 0:
        return MIN_SHARDS
    return max(MIN_SHARDS, min(MAX_SHARDS, math.ceil(total / target)))


def assign(bundles: list[str], costs: dict[str, float], count: int) -> list[dict[str, object]]:
    shards: list[dict[str, object]] = [{"shard": str(index), "bundles": [], "load": 0.0} for index in range(count)]
    for bundle in sorted(bundles, key=lambda name: (-costs[name], name)):
        lightest = min(shards, key=lambda shard: (shard["load"], int(shard["shard"])))
        lightest["bundles"].append(bundle)
        lightest["load"] = float(lightest["load"]) + costs[bundle]
    return shards


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Split a bundle list into balanced shards.")
    parser.add_argument("--bundles", required=True, help="space-separated bundle ids")
    parser.add_argument("--phase", choices=("pack", "test"), default="pack")
    parser.add_argument("--costs", type=Path, default=DEFAULT_COSTS)
    parser.add_argument("--target", type=float, default=600.0, help="seconds per shard to aim for")
    parser.add_argument("--shards", type=int, default=0, help="fixed shard count; 0 derives it from the target")
    parser.add_argument("--json", action="store_true", help="print the matrix entries instead of a summary")
    args = parser.parse_args(argv)

    bundles = args.bundles.split()
    if not bundles:
        print("shard-bundles: no bundles", file=sys.stderr)
        return 2
    costs = load_costs(args.costs, args.phase, bundles)
    total = sum(costs.values())
    count = args.shards if args.shards > 0 else shard_count(total, args.target)
    shards = assign(bundles, costs, count)

    if args.json:
        print(json.dumps([{"shard": shard["shard"], "bundles": " ".join(shard["bundles"])} for shard in shards]))
        return 0

    for shard in shards:
        print(f"shard {shard['shard']}: {int(shard['load'])}s  {' '.join(shard['bundles'])}")
    slowest = max(float(shard["load"]) for shard in shards)
    print(f"total {int(total)}s over {count} shards; slowest {int(slowest)}s")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
