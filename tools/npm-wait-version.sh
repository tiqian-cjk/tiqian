#!/usr/bin/env bash
# Wait until npm exposes the exact versions a downstream job needs.
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: tools/npm-wait-version.sh <package@version> ..." >&2
  exit 2
fi

pending=("$@")
deadline=$((SECONDS + 600))
while true; do
  # Once a version becomes visible, stop querying it while the others settle.
  missing=()
  for spec in "${pending[@]}"; do
    if shasum="$(npm view "$spec" dist.shasum --prefer-online --fetch-retries=0 --fetch-timeout=10000 2>/dev/null)" \
        && [[ "$shasum" =~ ^[[:xdigit:]]{40}$ ]]; then
      echo "$spec is visible in npm"
    else
      missing+=("$spec")
    fi
  done
  if [ "${#missing[@]}" -eq 0 ]; then exit 0; fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "::error::npm versions still unavailable after ten minutes: ${missing[*]}" >&2
    exit 1
  fi
  pending=("${missing[@]}")
  echo "Waiting for npm: ${pending[*]}"
  sleep 10
done
