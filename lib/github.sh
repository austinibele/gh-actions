#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# github.sh - GitHub API utilities
# -----------------------------------------------------------------------------
# Utilities for interacting with GitHub API, primarily for checking previous
# workflow run status to determine if a rebuild is needed.
#
# Public functions:
#   check_previous_run <job_pattern>
#     → Sets: PREVIOUS_FAILED ("true"|"false")
# -----------------------------------------------------------------------------
set -euo pipefail

# Public: Check if the previous workflow run for a job pattern failed
# job_pattern: Pattern to match in job names (e.g., "build-backend")
check_previous_run() {
  local job_pattern="${1:-}"

  if [[ -z "$job_pattern" ]]; then
    echo "check_previous_run: job_pattern parameter is required" >&2
    return 1
  fi

  echo "Checking previous run status..." >&2

  # Initialize default value
  PREVIOUS_FAILED="false"

  # Check if gh CLI is available
  if ! command -v gh &>/dev/null; then
    echo "gh CLI not available, skipping previous run check" >&2
    export PREVIOUS_FAILED
    return 0
  fi

  # Ensure the gh CLI is authenticated
  if [[ -z "${GH_TOKEN:-}" ]]; then
    export GH_TOKEN="${GITHUB_TOKEN:-${PAT:-}}"
  fi

  if [[ -z "${GH_TOKEN:-}" ]]; then
    echo "No GitHub token available, skipping previous run check" >&2
    export PREVIOUS_FAILED
    return 0
  fi

  # Validate required environment variables
  if [[ -z "${GITHUB_REPOSITORY:-}" ]] || [[ -z "${GITHUB_REF_NAME:-}" ]] || [[ -z "${GITHUB_RUN_ID:-}" ]]; then
    echo "Missing GitHub environment variables, skipping previous run check" >&2
    export PREVIOUS_FAILED
    return 0
  fi

  echo "Checking workflow runs for repository: $GITHUB_REPOSITORY, branch: $GITHUB_REF_NAME" >&2

  # Get the previous workflow run
  local workflow_name="${GITHUB_WORKFLOW:-}"
  local runs_response
  set +e
  if [[ -n "$workflow_name" ]]; then
    runs_response=$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs" \
      --jq ".workflow_runs[] | select(.name == \"${workflow_name}\" and .head_branch == \"${GITHUB_REF_NAME}\" and .id != ${GITHUB_RUN_ID}) | .id" 2>/dev/null)
  else
    runs_response=$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs" \
      --jq ".workflow_runs[] | select(.head_branch == \"${GITHUB_REF_NAME}\" and .id != ${GITHUB_RUN_ID}) | .id" 2>/dev/null)
  fi
  local gh_status=$?
  set -e

  if [[ $gh_status -ne 0 ]]; then
    echo "Failed to fetch workflow runs (exit $gh_status), skipping previous run check" >&2
    export PREVIOUS_FAILED
    return 0
  fi

  if [[ -z "$runs_response" ]]; then
    echo "No previous workflow runs found on branch '${GITHUB_REF_NAME}'" >&2
    export PREVIOUS_FAILED
    return 0
  fi

  # Get the first (most recent) run ID
  local previous_run_id
  previous_run_id=$(echo "$runs_response" | head -n 1)

  if [[ -z "$previous_run_id" ]]; then
    echo "No previous workflow run ID found" >&2
    export PREVIOUS_FAILED
    return 0
  fi

  echo "Found previous run ID: $previous_run_id" >&2

  # Get the jobs for that specific run
  local jobs_response
  set +e
  jobs_response=$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${previous_run_id}/jobs" \
    --jq ".jobs[] | select(.name | contains(\"${job_pattern}\")) | .conclusion" 2>/dev/null)
  local gh_status=$?
  set -e

  if [[ $gh_status -ne 0 ]]; then
    echo "Failed to fetch jobs for run ${previous_run_id}, skipping" >&2
    export PREVIOUS_FAILED
    return 0
  fi

  if [[ -z "$jobs_response" ]]; then
    echo "No jobs matching pattern '${job_pattern}' found in run ${previous_run_id}" >&2
    export PREVIOUS_FAILED
    return 0
  fi

  # Get the first job conclusion
  local previous_status
  previous_status=$(echo "$jobs_response" | head -n 1)

  if [[ "$previous_status" == "failure" ]]; then
    echo "Previous run failed" >&2
    PREVIOUS_FAILED="true"
  else
    echo "Previous run succeeded or was not a failure (status: ${previous_status:-unknown})" >&2
    PREVIOUS_FAILED="false"
  fi

  echo "Previous failed: $PREVIOUS_FAILED" >&2
  export PREVIOUS_FAILED
  return 0
}
