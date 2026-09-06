#!/usr/bin/env bash
# decide.sh
# Purpose: Thin adapter around build-decision.sh for package-lambda.
# Keeps package-lambda-specific required-env checks and singular-filter_pattern
# -> JSON-array normalization, then execs build-decision with CHECK_PREVIOUS_RUN=false.
# Prints GITHUB_OUTPUT lines (via build-decision):
#   should_build=true|false
#   reason=forced|ledger_missing|ledger_failed|source_changed|no_changes
#   last_success_sha=<sha or empty>
#   changed_files=<multiline when GITHUB_OUTPUT is set>
#
# Environment (required): ARTIFACT_ID, S3_BUCKET, ENV
# Environment (optional): FILTER_PATTERNS, LEDGER_PREFIX, FORCE_BUILD, GITHUB_SHA, PAT
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${ENV:-}" ]]; then
  echo "Error: ENV must be set for package-lambda ledger isolation (expected workflow env ENV)" >&2
  exit 1
fi

if [[ -z "${ARTIFACT_ID:-}" ]]; then
  echo "Error: ARTIFACT_ID must be set (package-lambda key_prefix)" >&2
  exit 1
fi

if [[ -z "${S3_BUCKET:-}" ]]; then
  echo "Error: S3_BUCKET must be set (package-lambda s3_bucket_name)" >&2
  exit 1
fi

if echo "${FILTER_PATTERNS:-}" | jq -e 'type=="array"' >/dev/null 2>&1; then
  patterns_json="$FILTER_PATTERNS"
else
  patterns_json=$(jq -cn --arg p "${FILTER_PATTERNS:-}" '[$p]')
fi

export CHECK_PREVIOUS_RUN=false FILTER_PATTERNS="$patterns_json"
exec bash "$SCRIPT_DIR/../build-decision/build-decision.sh"
