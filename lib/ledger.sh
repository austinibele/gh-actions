#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# ledger.sh - S3-based build status tracking
# -----------------------------------------------------------------------------
# Generic ledger system for tracking artifact build status in S3. Works with
# any artifact type (Docker images, Lambda functions, static sites, etc.).
#
# IMPORTANT: Ledger files are environment-specific to prevent dev/prod conflicts.
# The env parameter is REQUIRED to ensure correct isolation.
#
# Public functions:
#   ledger_check <artifact_id> <sha> <bucket> <env> [prefix]
#     → Sets: LEDGER_SHOULD_BUILD ("true"|"false")
#     → Sets: LEDGER_LAST_SUCCESS_SHA (commit SHA or empty)
#     → Sets: LEDGER_FILE_EXISTS ("true"|"false")
#
#   ledger_write <artifact_id> <status> <sha> <bucket> <env> [prefix]
#     → Writes status record to S3
#     → status: "success" | "failure" | "building"
# -----------------------------------------------------------------------------
set -euo pipefail

# Internal: download ledger JSON to stdout
# Returns 0 if object exists, 1 otherwise
_ledger_fetch() {
  local bucket="$1" artifact_id="$2" env="$3" prefix="$4"
  local key="${prefix}${env}/${artifact_id}.json"
  local tmpfile
  tmpfile="$(mktemp)"

  if aws s3 cp "s3://${bucket}/${key}" "${tmpfile}" 1>/dev/null 2>&1; then
    cat "${tmpfile}"
    rm -f "${tmpfile}"
    return 0
  else
    rm -f "${tmpfile}"
    return 1
  fi
}

# Public: Check ledger state and decide if artifact should be rebuilt
# Sets LEDGER_SHOULD_BUILD ("true"|"false"), LEDGER_LAST_SUCCESS_SHA, and LEDGER_FILE_EXISTS ("true"|"false")
ledger_check() {
  local artifact_id="$1"
  local sha="$2"
  local bucket="${3:-${LEDGER_BUCKET:-}}"
  local env="${4:-${ENV:-}}"
  local prefix="${5:-build-ledger/}"

  if [[ -z "${bucket}" ]]; then
    echo "ledger_check: S3 bucket must be provided via arg or LEDGER_BUCKET env var" >&2
    return 1
  fi

  if [[ -z "${env}" ]]; then
    echo "ledger_check: env must be provided via arg or ENV env var" >&2
    return 1
  fi

  # Default to true until proven otherwise (missing file or errors force build)
  LEDGER_SHOULD_BUILD="true"
  LEDGER_LAST_SUCCESS_SHA=""
  LEDGER_FILE_EXISTS="false"

  local json status last_success_sha
  if ! json=$(_ledger_fetch "${bucket}" "${artifact_id}" "${env}" "${prefix}"); then
    # Ledger file missing – need build
    export LEDGER_SHOULD_BUILD LEDGER_LAST_SUCCESS_SHA LEDGER_FILE_EXISTS
    return 0
  fi

  LEDGER_FILE_EXISTS="true"
  status="$(echo "${json}" | jq -r '.status // "unknown"')"
  last_success_sha="$(echo "${json}" | jq -r '.last_success_sha // ""')"

  # Export for callers that want a diff base
  LEDGER_LAST_SUCCESS_SHA="$last_success_sha"

  # If status not success, we must rebuild
  if [[ "${status}" != "success" ]]; then
    LEDGER_SHOULD_BUILD="true"
    export LEDGER_SHOULD_BUILD LEDGER_LAST_SUCCESS_SHA LEDGER_FILE_EXISTS
    return 0
  fi

  # Status success – leave rebuild decision to file-level diff; default to skip
  LEDGER_SHOULD_BUILD="false"
  export LEDGER_SHOULD_BUILD LEDGER_LAST_SUCCESS_SHA LEDGER_FILE_EXISTS
  return 0
}

# Public: Write status record to S3 ledger
# status: "success" | "failure" | "building"
ledger_write() {
  local artifact_id="$1"
  local status="$2"
  local sha="$3"
  local bucket="${4:-${LEDGER_BUCKET:-}}"
  local env="${5:-${ENV:-}}"
  local prefix="${6:-build-ledger/}"

  if [[ -z "${bucket}" ]]; then
    echo "ledger_write: S3 bucket must be provided via arg or LEDGER_BUCKET env var" >&2
    return 1
  fi

  if [[ -z "${env}" ]]; then
    echo "ledger_write: env must be provided via arg or ENV env var" >&2
    return 1
  fi

  local key="${prefix}${env}/${artifact_id}.json"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  local json_content
  json_content=$(cat <<EOF
{
  "artifact_id": "${artifact_id}",
  "status": "${status}",
  "last_attempt_sha": "${sha}",
  "last_attempt_ts": "${ts}"$(
    if [[ "${status}" == "success" ]]; then
      printf ',\n  "last_success_sha": "%s",\n  "last_success_ts": "%s"' "${sha}" "${ts}"
    fi
  )
}
EOF
)

  echo "${json_content}" | aws s3 cp - "s3://${bucket}/${key}"
}
