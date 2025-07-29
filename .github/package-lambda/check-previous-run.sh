#!/usr/bin/env bash
# check-previous-run.sh
# Purpose: Determine whether the most recent previous workflow run for the same branch failed.
# Prints "previous_failed=true" or "previous_failed=false".
# Usage: check-previous-run.sh <repository> <branch> <current_run_id> <key_prefix>

set -euo pipefail

usage() { echo "Usage: $0 --repo <org/repo> --branch <branch> --run-id <id> --key-prefix <prefix>" >&2; exit 1; }

REPO=""; BRANCH=""; CURRENT_RUN_ID=""; KEY_PREFIX="";

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --run-id) CURRENT_RUN_ID="$2"; shift 2 ;;
    --key-prefix) KEY_PREFIX="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$REPO" || -z "$BRANCH" || -z "$CURRENT_RUN_ID" || -z "$KEY_PREFIX" ]] && usage

PREVIOUS_RUN_ID=$(gh api \
  "repos/${REPO}/actions/runs" \
  --jq ".workflow_runs[] | select(.head_branch == \"${BRANCH}\" and .id != ${CURRENT_RUN_ID}) | .id" \
  | head -n 1 || echo "")

if [[ -z "$PREVIOUS_RUN_ID" ]]; then
  echo "previous_failed=false"
  exit 0
fi

PREVIOUS_STATUS=$(gh api \
  "repos/${REPO}/actions/runs/${PREVIOUS_RUN_ID}/jobs" \
  --jq ".jobs[] | select(.name | contains(\"package-${KEY_PREFIX}\")) | .conclusion" \
  | head -n 1 || echo "")

if [[ "$PREVIOUS_STATUS" == "failure" ]]; then
  echo "previous_failed=true"
else
  echo "previous_failed=false"
fi 