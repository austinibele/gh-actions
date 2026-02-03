#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# change-detection.sh - File change detection via git
# -----------------------------------------------------------------------------
# Detects file changes between commits using git diff. Supports glob pattern
# matching to filter changes relevant to specific artifacts.
#
# Public functions:
#   detect_changes <filter_patterns_json> [base_sha]
#     → Sets: CHANGES_DETECTED ("true"|"false")
#     → Sets: CHANGED_FILES (newline-separated list)
# -----------------------------------------------------------------------------
set -euo pipefail

# Internal: Check if a file matches any of the filter patterns
# Returns 0 if match found, 1 otherwise
_matches_patterns() {
  local file="$1"
  shift
  local patterns=("$@")

  for pattern in "${patterns[@]}"; do
    [[ -z "$pattern" ]] && continue

    # Remove surrounding quotes if present
    pattern="${pattern#\"}"
    pattern="${pattern%\"}"

    # Exact match
    if [[ "$file" == $pattern ]]; then
      echo "File '$file' matches pattern '$pattern'" >&2
      return 0
    fi

    # Handle patterns ending with /** or **
    if [[ "$pattern" == *'/**' ]]; then
      local base_pattern="${pattern%/**}"
      if [[ "$file" == "$base_pattern/"* ]]; then
        echo "File '$file' matches pattern '$pattern'" >&2
        return 0
      fi
    elif [[ "$pattern" == *'**' ]]; then
      local base_pattern="${pattern%**}"
      if [[ "$file" == "$base_pattern"* ]]; then
        echo "File '$file' matches pattern '$pattern'" >&2
        return 0
      fi
    fi
  done

  return 1
}

# Public: Detect file changes between commits and filter by patterns
# filter_patterns_json: JSON array of glob patterns (e.g., '["src/**", "package.json"]')
# base_sha: SHA to diff against (defaults to HEAD^)
detect_changes() {
  local filter_patterns_json="${1:-}"
  local base_sha="${2:-}"

  echo "Detecting changes..." >&2

  # Initialize outputs
  CHANGES_DETECTED="false"
  CHANGED_FILES=""

  # If no filter pattern provided, assume changes
  if [[ -z "$filter_patterns_json" ]]; then
    CHANGES_DETECTED="true"
    echo "No filter pattern provided, assuming changes" >&2
    export CHANGES_DETECTED CHANGED_FILES
    return 0
  fi

  # Determine base commit
  local prev_commit
  if [[ -n "$base_sha" ]]; then
    prev_commit="$base_sha"
  elif [[ -n "${GITHUB_EVENT_BEFORE:-}" ]] && git cat-file -e "${GITHUB_EVENT_BEFORE}^{commit}" 2>/dev/null; then
    prev_commit="$GITHUB_EVENT_BEFORE"
  else
    prev_commit="$(git rev-parse HEAD^ 2>/dev/null || echo "")"
  fi

  if [[ -z "$prev_commit" ]]; then
    echo "Could not determine base commit, assuming changes" >&2
    CHANGES_DETECTED="true"
    export CHANGES_DETECTED CHANGED_FILES
    return 0
  fi

  local current_commit="${GITHUB_SHA:-$(git rev-parse HEAD)}"
  echo "Comparing commits: $prev_commit...$current_commit" >&2

  # Get changed files using git diff
  local changed_files
  changed_files=$(git diff --name-only "$prev_commit" "$current_commit" 2>/dev/null || echo "")

  if [[ -z "$changed_files" ]]; then
    echo "No changed files detected" >&2
    CHANGES_DETECTED="false"
    export CHANGES_DETECTED CHANGED_FILES
    return 0
  fi

  CHANGED_FILES="$changed_files"

  echo "Changed files:" >&2
  echo "$changed_files" | while read -r file; do
    [[ -n "$file" ]] && echo "  $file" >&2
  done

  # Parse filter patterns from JSON array
  local patterns_raw
  patterns_raw=$(echo "$filter_patterns_json" | jq -r '.[]' 2>/dev/null || echo "")

  if [[ -z "$patterns_raw" ]]; then
    echo "Could not parse filter patterns, assuming changes" >&2
    CHANGES_DETECTED="true"
    export CHANGES_DETECTED CHANGED_FILES
    return 0
  fi

  echo "Filter patterns:" >&2
  echo "$patterns_raw" | while read -r pattern; do
    [[ -n "$pattern" ]] && echo "  $pattern" >&2
  done

  # Convert patterns to array
  local patterns=()
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] && patterns+=("$pattern")
  done <<< "$patterns_raw"

  # Check if any changed file matches the patterns
  while IFS= read -r changed_file; do
    [[ -z "$changed_file" ]] && continue
    if _matches_patterns "$changed_file" "${patterns[@]}"; then
      CHANGES_DETECTED="true"
      echo "Changes detected: $CHANGES_DETECTED" >&2
      export CHANGES_DETECTED CHANGED_FILES
      return 0
    fi
  done <<< "$changed_files"

  echo "No matching changes detected" >&2
  export CHANGES_DETECTED CHANGED_FILES
  return 0
}
