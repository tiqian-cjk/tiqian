#!/usr/bin/env python3
"""Split a bundle list into balanced shards.

Each bundle costs a different amount of runner time, and every shard also pays a
fixed cost before its first bundle: the checkout, the Nix install and the
development shell. A round-robin split therefore leaves one shard far behind the
rest, and too many shards spend more time on that fixed cost than on the work.

This assigns the bundles longest-first to the shard with the least load and picks
the shard count that minimises the slowest shard plus the fixed cost. The table in
tools/shard-costs.json supplies the per-bundle seconds; the pipeline prints one
"shard timing" line per bundle, which is where those values come from.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

DEFAULT_COSTS = Path(__file__).with_name("shard-costs.json")
DEFAULT_OVERHEAD = 240.0
MAX_SHARDS = 13
MIN_SHARDS = 2


def load_costs(path: Path, phase: str, bundles: list[str]) -> dict[str, float]:
    table = json.loads(path.read_text())
    phase_costs = {str(key): float(value) for key, value in table.get(phase, {}).items()}
    known = sorted(phase_costs.values())
    median = known[len(known) // 2] if known else 60.0
    return {bundle: float(phase_costs.get(bundle, median)) for bundle in bundles}


def assign(bundles: list[str], costs: dict[str, float], count: int) -> list[dict[str, object]]:
    shards: list[dict[str, object]] = [{"shard": str(index), "bundles": [], "load": 0.0} for index in range(count)]
    for bundle in sorted(bundles, key=lambda name: (-costs[name], name)):
        lightest = min(shards, key=lambda shard: (shard["load"], int(shard["shard"])))
        lightest["bundles"].append(bundle)
        lightest["load"] = float(lightest["load"]) + costs[bundle]
    return shards


def best_split(bundles: list[str], costs: dict[str, float], overhead: float, limit: int) -> tuple[float, int, list[dict[str, object]]]:
    upper = max(MIN_SHARDS, min(limit, MAX_SHARDS, len(bundles)))
    best: tuple[float, int, list[dict[str, object]]] | None = None
    for count in range(MIN_SHARDS, upper + 1):
        shards = assign(bundles, costs, count)
        slowest = max(float(shard["load"]) for shard in shards)
        cost = slowest + overhead
        if best is None or cost < best[0] - 1e-9:
            best = (cost, count, shards)
    assert best is not None
    return best


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Split a bundle list into balanced shards.")
    parser.add_argument("--bundles", required=True, help="space-separated bundle ids")
    parser.add_argument("--phase", choices=("pack", "test"), default="pack")
    parser.add_argument("--costs", type=Path, default=DEFAULT_COSTS)
    parser.add_argument("--overhead", type=float, default=DEFAULT_OVERHEAD, help="seconds every shard pays before its first bundle")
    parser.add_argument("--shards", type=int, default=0, help="fixed shard count; 0 derives it")
    parser.add_argument("--limit", type=int, default=MAX_SHARDS, help="highest shard count to consider")
    parser.add_argument("--json", action="store_true", help="print the matrix entries instead of a summary")
    args = parser.parse_args(argv)

    bundles = args.bundles.split()
    if not bundles:
        print("shard-bundles: no bundles", file=sys.stderr)
        return 2
    costs = load_costs(args.costs, args.phase, bundles)
    total = sum(costs.values())

    if args.shards > 0:
        count = args.shards
        shards = assign(bundles, costs, count)
        cost = max(float(shard["load"]) for shard in shards) + args.overhead
    else:
        cost, count, shards = best_split(bundles, costs, args.overhead, args.limit)

    if args.json:
        print(json.dumps([{"shard": shard["shard"], "bundles": " ".join(shard["bundles"])} for shard in shards]))
        return 0

    for shard in shards:
        print(f"shard {shard['shard']}: {int(shard['load'])}s work  {' '.join(shard['bundles'])}")
    slowest = max(float(shard["load"]) for shard in shards)
    print(
        f"{args.phase}: {int(total)}s of work over {count} shards; "
        f"slowest {int(slowest)}s work + {int(args.overhead)}s fixed = {int(cost)}s per pipeline run"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
