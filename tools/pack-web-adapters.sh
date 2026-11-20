#!/usr/bin/env bash
# Requires an installed workspace and built runtime, core, web-component and precompute packages.
# Packs all adapters with their prepack checks, then installs each archive from a clean project.
set -euo pipefail

destination="${1:?pass an output directory}"
version="${2:?pass the release version}"
root="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$destination"
destination="$(cd "$destination" && pwd)"

for adapter in astro sveltekit react; do
  package="@tiqian/$adapter"
  entry="$package"
  component=""
  case "$adapter" in
    astro) component="TiqianProse.astro" ;;
    sveltekit)
      component="TiqianProse.svelte"
      entry="$package/server"
      ;;
  esac

  tarball="$destination/tiqian-$adapter-$version.tgz"
  (
    cd "$root/platforms/web/client/$adapter"
    if [[ "$(node -p "require('./package.json').version")" != "$version" ]]; then
      echo "$package package.json does not match release version $version" >&2
      exit 1
    fi
    npm pack --foreground-scripts --pack-destination "$destination"
  )
  if [[ -n "$component" ]]; then
    tar -xOf "$tarball" "package/$component" > /dev/null
  fi
  python3 "$root/tools/publish-contract.py" --archive "$tarball"
  bash "$root/tools/check-npm-package.sh" "$tarball" --expect "$package" --entry "$entry"
done
