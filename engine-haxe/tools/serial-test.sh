#!/usr/bin/env bash
# Serialize test runs across parallel lanes (2026-08-31 ruling: tests never
# run in parallel; implementation and compilation may). Every test command a
# lane or the center runs goes through this script. It blocks on an exclusive
# flock so tests queue one at a time across worktrees, agents, and sessions,
# then runs the command unchanged and forwards its exit status.
#
# Usage: serial-test.sh <command> [args...]
#   TIQIAN_TEST_LOCK   lock path  (default /tmp/tiqian-serial-test.lock)
#   TIQIAN_TEST_LOG    log path   (default /tmp/tiqian-serial-test.log)
#
# The lock and log live outside the worktrees so every lane serializes on the
# same queue. The log records acquire/release lines so a stuck queue is
# diagnosable: the last acquired line without a matching release names the
# holder.
set -u

LOCK="${TIQIAN_TEST_LOCK:-/tmp/tiqian-serial-test.lock}"
LOG="${TIQIAN_TEST_LOG:-/tmp/tiqian-serial-test.log}"

if [ "$#" -eq 0 ]; then
  echo "usage: serial-test.sh <command> [args...]" >&2
  exit 2
fi

exec 9>"$LOCK"
flock 9

printf '[serial-test] %s acquired: %s\n' "$(date -Is)" "$*" >>"$LOG"
"$@"
status=$?
printf '[serial-test] %s released rc=%s: %s\n' "$(date -Is)" "$status" "$*" >>"$LOG"

exit "$status"
