#!/usr/bin/env python3
"""Set every package version in the project file to the release version.

The registry derives artifact names from <package>-<version> and the tag, so a
packed manifest that still carries the placeholder version produces a download
URL that cannot exist.

Usage: align-package-versions.py <version> [project path]
"""
import json
import pathlib
import re
import sys


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: align-package-versions.py <version> [project]")
    version = sys.argv[1]
    path = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "boring.json")
    text = path.read_text()

    def bump(match):
        body = match.group(0)
        return re.sub(r'"version": "[^"]*"', '"version": "%s"' % version, body, count=1)

    updated = re.sub(r'"package":\s*\{[^{}]*\}', bump, text)
    path.write_text(updated)
    clean = re.sub(r"^\s*//.*$", "", updated, flags=re.M)
    json.loads(clean)
    bundles = [b for b in json.loads(clean)["bundles"] if "package" in b]
    print("aligned %d packages to %s" % (len(bundles), version))


if __name__ == "__main__":
    main()
