#!/usr/bin/env bash
# decide.sh
# Purpose: Decide whether package-lambda should zip, using the S3 build ledger
# and change detection against last_success_sha. Prints GITHUB_OUTPUT lines:
#   should_build=true|false
#   reason=forced|ledger_missing|ledger_failed|source_changed|no_changes
#   last_success_sha=<sha or empty>
#
# Environment (required): ARTIFACT_ID, S3_BUCKET, ENV
# Environment (optional): FILTER_PATTERNS, LEDGER_PREFIX, FORCE_BUILD, GITHUB_SHA, PAT
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../lib"

# LIB_DIR is resolved at runtime; shellcheck cannot follow it.
# shellcheck disable=SC1091
source "${LIB_DIR}/ledger.sh"
# shellcheck disable=SC1091
source "${LIB_DIR}/change-detection.sh"

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

if [[ "${FORCE_BUILD:-false}" == "true" || "${FORCE_BUILD:-0}" == "1" ]]; then
  echo "should_build=true"
  echo "reason=forced"
  echo "last_success_sha="
  exit 0
fi

if echo "${FILTER_PATTERNS:-}" | jq -e 'type=="array"' >/dev/null 2>&1; then
  patterns_json="$FILTER_PATTERNS"
else
  patterns_json=$(jq -cn --arg p "${FILTER_PATTERNS:-}" '[$p]')
fi

ledger_check "$ARTIFACT_ID" "${GITHUB_SHA:-HEAD}" "$S3_BUCKET" "$ENV" "${LEDGER_PREFIX:-build-ledger/}"

last_success_sha="${LEDGER_LAST_SUCCESS_SHA:-}"

if [[ "${LEDGER_SHOULD_BUILD}" == "true" ]]; then
  reason="ledger_missing"
  if [[ "${LEDGER_FILE_EXISTS:-false}" == "true" ]]; then
    reason="ledger_failed"
  fi
  echo "should_build=true"
  echo "reason=${reason}"
  echo "last_success_sha=${last_success_sha}"
  exit 0
fi

detect_changes "$patterns_json" "$last_success_sha"

if [[ "${CHANGES_DETECTED}" == "true" ]]; then
  echo "should_build=true"
  echo "reason=source_changed"
  echo "last_success_sha=${last_success_sha}"
  exit 0
fi

echo "should_build=false"
echo "reason=no_changes"
echo "last_success_sha=${last_success_sha}"
