#!/usr/bin/env bash
# reuse.sh
# Purpose: Verify an existing Lambda zip can be reused after a no_changes decision.
# Writes GITHUB_OUTPUT lines:
#   hit=true|false
#   s3_key=<key> (on hit)
#   reason=reuse_miss (on not-found miss)
# Exits 1 if last_success_sha is empty (ledger invariant) or head-object fails
# for a reason other than not-found.
#
# Environment (required): LAST_SUCCESS_SHA, KEY_PREFIX, S3_BUCKET, BRANCH
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_PATH="${GITHUB_ACTION_PATH:-$SCRIPT_DIR}"

write_output() {
  local name="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${name}=${value}" >> "$GITHUB_OUTPUT"
  fi
  echo "${name}=${value}"
}

if [[ -z "${LAST_SUCCESS_SHA:-}" ]]; then
  echo "Invariant violation: ledger reported success but last_success_sha is empty; cannot reuse a zip" >&2
  exit 1
fi

if [[ -z "${KEY_PREFIX:-}" || -z "${S3_BUCKET:-}" || -z "${BRANCH:-}" ]]; then
  echo "Error: KEY_PREFIX, S3_BUCKET, and BRANCH must be set" >&2
  exit 1
fi

helper="${ACTION_PATH}/determine-env-and-key.sh"
if [[ ! -f "$helper" ]]; then
  echo "Missing helper: $helper" >&2
  exit 1
fi

eval "$(bash "$helper" --branch "$BRANCH" --key-prefix "$KEY_PREFIX" --sha "$LAST_SUCCESS_SHA")"
if [[ -z "${s3_key:-}" ]]; then
  echo "Failed to compute reuse s3_key" >&2
  exit 1
fi

set +e
head_stderr=$(aws s3api head-object --bucket "$S3_BUCKET" --key "$s3_key" 2>&1 >/dev/null)
head_rc=$?
set -e

if [[ "$head_rc" -eq 0 ]]; then
  echo "Reusing existing Lambda package $s3_key" >&2
  write_output "s3_key" "$s3_key"
  write_output "hit" "true"
  exit 0
fi

if [[ "$head_stderr" == *'404'* || "$head_stderr" == *'NotFound'* || "$head_stderr" == *'Not Found'* ]]; then
  echo "Reuse key $s3_key is missing; will package" >&2
  write_output "hit" "false"
  write_output "reason" "reuse_miss"
  exit 0
fi

echo "Failed to check reuse key $s3_key (aws exit ${head_rc})" >&2
echo "$head_stderr" >&2
exit 1
