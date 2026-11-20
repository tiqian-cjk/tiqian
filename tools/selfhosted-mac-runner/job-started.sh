#!/usr/bin/env bash
#
# ACTIONS_RUNNER_HOOK_JOB_STARTED hook for the self-hosted macOS runner that
# builds the Neon addon (build-neon-precompute.yml, macOS leg).
#
# The runner may be registered with the custom label tiqian-mac-arm64. This
# hook runs before every job and refuses everything the workflow should not
# send here:
#
#   * push events are accepted only for tag refs (refs/tags/*);
#   * workflow_dispatch is accepted;
#   * every other event is refused;
#   * a pull request whose head repository is a fork is refused, and a
#     pull_request payload whose fork state cannot be read is refused;
#   * GITHUB_ACTOR must be listed in allow-actors.txt next to this script.
#
# Every refusal prints a reason to stderr and exits non-zero. Missing or empty
# environment variables are treated as refusals, never as permission.
#
# Requirements: bash and python3 (the Command Line Tools provide python3 on
# macOS). The runner needs python3 available on PATH when it starts the job.
set -euo pipefail

readonly script_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly allow_file="${script_dir}/allow-actors.txt"

refuse() {
  printf 'selfhosted-mac-runner: rejected: %s\n' "$1" >&2
  exit 1
}

event_name="${GITHUB_EVENT_NAME:-}"
if [[ -z "${event_name}" ]]; then
  refuse "GITHUB_EVENT_NAME is unset"
fi

case "${event_name}" in
  push)
    ref="${GITHUB_REF:-}"
    if [[ -z "${ref}" ]]; then
      refuse "GITHUB_REF is unset for a push event"
    fi
    case "${ref}" in
      refs/tags/*) ;;
      *) refuse "push events are accepted only for tag refs (refs/tags/*), got '${ref}'" ;;
    esac
    ;;
  workflow_dispatch) ;;
  *)
    refuse "event '${event_name}' is not accepted; only tag pushes and workflow_dispatch run here"
    ;;
esac

event_path="${GITHUB_EVENT_PATH:-}"
if [[ -z "${event_path}" ]]; then
  refuse "GITHUB_EVENT_PATH is unset"
fi
if [[ ! -f "${event_path}" ]]; then
  refuse "GITHUB_EVENT_PATH '${event_path}' is not a regular file"
fi

fork_state="$(python3 - "${event_path}" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        payload = json.load(handle)
except Exception as exc:  # noqa: BLE001 - any read/parse failure is a refusal
    print(f"cannot read the event payload: {exc}", file=sys.stderr)
    sys.exit(2)

pull_request = payload.get("pull_request")
if pull_request is None:
    print("clean")
    sys.exit(0)

if not isinstance(pull_request, dict):
    print("cannot inspect pull_request: expected an object", file=sys.stderr)
    sys.exit(2)

head = pull_request.get("head")
if not isinstance(head, dict):
    print("cannot inspect pull_request.head: expected an object", file=sys.stderr)
    sys.exit(2)

repo = head.get("repo")
if repo is None:
    # A deleted fork head has no repository object, so the fork state is
    # unknown. Refuse instead of guessing.
    print("fork")
    sys.exit(0)

if not isinstance(repo, dict):
    print("cannot inspect pull_request.head.repo: expected an object", file=sys.stderr)
    sys.exit(2)

fork = repo.get("fork")
if fork is True:
    print("fork")
elif fork is False:
    print("clean")
else:
    print("cannot determine pull_request.head.repo.fork", file=sys.stderr)
    sys.exit(2)
PY
)" || refuse "could not inspect the event payload at '${event_path}'"

case "${fork_state}" in
  clean) ;;
  fork) refuse "pull requests from forks may not run here" ;;
  *) refuse "unexpected event payload inspection result '${fork_state}'" ;;
esac

actor="${GITHUB_ACTOR:-}"
if [[ -z "${actor}" ]]; then
  refuse "GITHUB_ACTOR is unset"
fi
if [[ ! -f "${allow_file}" ]]; then
  refuse "actor allowlist '${allow_file}' is missing"
fi

actor_allowed=0
while IFS= read -r line || [[ -n "${line}" ]]; do
  line="${line%$'\r'}"
  line="${line%%#*}"
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line%"${line##*[![:space:]]}"}"
  if [[ -n "${line}" && "${line}" == "${actor}" ]]; then
    actor_allowed=1
    break
  fi
done < "${allow_file}"

if [[ "${actor_allowed}" -ne 1 ]]; then
  refuse "actor '${actor}' is not listed in '${allow_file}'"
fi

printf 'selfhosted-mac-runner: accepted %s for actor %s\n' "${event_name}" "${actor}"
