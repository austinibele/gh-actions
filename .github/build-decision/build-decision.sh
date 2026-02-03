#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# build-decision.sh - Orchestration script for build decision action
# -----------------------------------------------------------------------------
# Combines ledger check, change detection, and previous run status to decide
# whether an artifact should be built.
#
# Decision Matrix:
# | Ledger Status | Source Changed | Previous Failed | Result |
# |---------------|----------------|-----------------|--------|
# | missing       | *              | *               | build (reason: ledger_missing) |
# | failure       | *              | *               | build (reason: ledger_failed) |
# | success       | true           | *               | build (reason: source_changed) |
# | success       | false          | true            | build (reason: previous_failed) |
# | success       | false          | false           | skip (reason: no_changes) |
#
# Environment variables (required):
#   ARTIFACT_ID      - Unique identifier for the artifact
#   FILTER_PATTERNS  - JSON array of glob patterns
#   S3_BUCKET        - S3 bucket for ledger storage
#
# Environment variables (optional):
#   LEDGER_PREFIX        - S3 key prefix (default: build-ledger/)
#   CHECK_PREVIOUS_RUN   - Check previous run status (default: true)
#   JOB_PATTERN          - Pattern to match job name
#   FORCE_BUILD          - Force rebuild (default: false)
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/../../lib"

# Source libraries
source "${LIB_DIR}/ledger.sh"
source "${LIB_DIR}/change-detection.sh"
source "${LIB_DIR}/github.sh"

# Helper: write output to GITHUB_OUTPUT
write_output() {
  local name="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${name}=${value}" >> "$GITHUB_OUTPUT"
  fi
  echo "${name}=${value}"
}

# Helper: write multiline output to GITHUB_OUTPUT
write_output_multiline() {
  local name="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "${name}<<EOF"
      echo "$value"
      echo "EOF"
    } >> "$GITHUB_OUTPUT"
  fi
}

main() {
  echo "=== Build Decision for ${ARTIFACT_ID} ===" >&2

  # Handle force build
  if [[ "${FORCE_BUILD:-false}" == "true" || "${FORCE_BUILD:-0}" == "1" ]]; then
    echo "Force build enabled" >&2
    write_output "should_build" "true"
    write_output "reason" "forced"
    write_output "last_success_sha" ""
    write_output "changed_files" ""
    return 0
  fi

  # Step 1: Check ledger status
  echo "Step 1: Checking ledger status..." >&2
  ledger_check "$ARTIFACT_ID" "${GITHUB_SHA:-HEAD}" "$S3_BUCKET" "${LEDGER_PREFIX:-build-ledger/}"

  local last_success_sha="${LEDGER_LAST_SUCCESS_SHA:-}"

  # If ledger says we should build (missing or failed status)
  if [[ "$LEDGER_SHOULD_BUILD" == "true" ]]; then
    # Determine reason based on whether ledger file exists
    local reason="ledger_missing"
    if [[ "${LEDGER_FILE_EXISTS:-false}" == "true" ]]; then
      reason="ledger_failed"
    fi
    echo "Ledger indicates build needed (reason: $reason)" >&2
    write_output "should_build" "true"
    write_output "reason" "$reason"
    write_output "last_success_sha" "$last_success_sha"
    write_output "changed_files" ""
    return 0
  fi

  # Step 2: Check for source changes
  echo "Step 2: Checking for source changes..." >&2
  detect_changes "$FILTER_PATTERNS" "$last_success_sha"

  write_output_multiline "changed_files" "${CHANGED_FILES:-}"

  if [[ "$CHANGES_DETECTED" == "true" ]]; then
    echo "Source changes detected" >&2
    write_output "should_build" "true"
    write_output "reason" "source_changed"
    write_output "last_success_sha" "$last_success_sha"
    return 0
  fi

  # Step 3: Check previous run status (optional)
  if [[ "${CHECK_PREVIOUS_RUN:-true}" == "true" || "${CHECK_PREVIOUS_RUN:-1}" == "1" ]]; then
    echo "Step 3: Checking previous run status..." >&2
    local job_pattern="${JOB_PATTERN:-$ARTIFACT_ID}"
    check_previous_run "$job_pattern"

    if [[ "$PREVIOUS_FAILED" == "true" ]]; then
      echo "Previous run failed, triggering rebuild" >&2
      write_output "should_build" "true"
      write_output "reason" "previous_failed"
      write_output "last_success_sha" "$last_success_sha"
      return 0
    fi
  fi

  # No build needed
  echo "No build needed" >&2
  write_output "should_build" "false"
  write_output "reason" "no_changes"
  write_output "last_success_sha" "$last_success_sha"
  return 0
}

main "$@"
