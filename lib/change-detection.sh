#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# change-detection.sh - File change detection via git
# -----------------------------------------------------------------------------
# Detects file changes between commits using git diff. Supports glob pattern
# matching to filter changes relevant to specific artifacts.
#
# Submodule support: When a submodule changes, this script will checkout the
# submodule and inspect the actual file changes within it, mapping them back
# to full repository paths for pattern matching.
#
# Public functions:
#   detect_changes <filter_patterns_json> [base_sha]
#     → Sets: CHANGES_DETECTED ("true"|"false")
#     → Sets: CHANGED_FILES (newline-separated list)
#
# Environment variables:
#   PAT - Personal access token for private submodule access (optional)
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

# Internal: Check if a path could match any filter pattern (prefix check)
_could_match_patterns() {
  local submodule_path="$1"
  shift
  local patterns=("$@")

  for pattern in "${patterns[@]}"; do
    [[ -z "$pattern" ]] && continue
    pattern="${pattern#\"}"
    pattern="${pattern%\"}"

    # Check if pattern starts with submodule path
    if [[ "$pattern" == "$submodule_path/"* ]] || [[ "$pattern" == "$submodule_path/**" ]]; then
      return 0
    fi
    # Check if pattern exactly matches submodule path
    if [[ "$pattern" == "$submodule_path" ]]; then
      return 0
    fi
  done
  return 1
}

# Internal: Get submodule paths from .gitmodules
_get_submodule_paths() {
  if [[ -f .gitmodules ]]; then
    grep '^\s*path\s*=' .gitmodules | sed 's/.*=\s*//' | tr -d ' '
  fi
}

# Internal: Configure git for private repo access
_configure_git_for_submodules() {
  if [[ -n "${PAT:-}" ]]; then
    echo "Configuring git for submodule access..." >&2
    git config --global url."https://${PAT}@github.com/".insteadOf "https://github.com/"
  fi
}

# Internal: Get submodule commit SHAs from diff
# Returns: "old_sha new_sha" or empty if not a submodule change
_get_submodule_commits() {
  local submodule_path="$1"
  local base_commit="$2"
  local head_commit="$3"

  # Get the submodule commit at base
  local old_sha
  old_sha=$(git ls-tree "$base_commit" -- "$submodule_path" 2>/dev/null | awk '{print $3}' || echo "")

  # Get the submodule commit at head
  local new_sha
  new_sha=$(git ls-tree "$head_commit" -- "$submodule_path" 2>/dev/null | awk '{print $3}' || echo "")

  if [[ -n "$old_sha" ]] && [[ -n "$new_sha" ]] && [[ "$old_sha" != "$new_sha" ]]; then
    echo "$old_sha $new_sha"
  fi
}

# Internal: Get changed files within a submodule
_get_submodule_changed_files() {
  local submodule_path="$1"
  local old_sha="$2"
  local new_sha="$3"

  echo "Checking changes in submodule '$submodule_path' ($old_sha..$new_sha)..." >&2

  # Initialize/update just this submodule
  git submodule update --init "$submodule_path" 2>/dev/null || {
    echo "Warning: Failed to checkout submodule '$submodule_path'" >&2
    return 1
  }

  # Get changed files within the submodule
  local submodule_files
  submodule_files=$(git -C "$submodule_path" diff --name-only "$old_sha" "$new_sha" 2>/dev/null || echo "")

  if [[ -n "$submodule_files" ]]; then
    # Prefix each file with the submodule path
    echo "$submodule_files" | while read -r file; do
      [[ -n "$file" ]] && echo "${submodule_path}/${file}"
    done
  fi
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

  # Ensure the base commit is reachable (shallow clones may not have it)
  if ! git cat-file -e "${prev_commit}^{commit}" 2>/dev/null; then
    echo "Base commit $prev_commit not in local history, fetching..." >&2
    git fetch --depth=1 origin "$prev_commit" 2>/dev/null || {
      echo "Warning: Could not fetch base commit $prev_commit, assuming changes" >&2
      CHANGES_DETECTED="true"
      export CHANGES_DETECTED CHANGED_FILES
      return 0
    }
  fi

  # Get changed files using git diff
  local changed_files
  changed_files=$(git diff --name-only "$prev_commit" "$current_commit" 2>/dev/null || echo "")

  if [[ -z "$changed_files" ]]; then
    echo "No changed files detected" >&2
    CHANGES_DETECTED="false"
    export CHANGES_DETECTED CHANGED_FILES
    return 0
  fi

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

  # Get list of submodules
  local submodules
  submodules=$(_get_submodule_paths)

  # Build list of all changed files (including expanded submodule changes)
  local all_changed_files="$changed_files"

  # Check for submodule changes and expand them
  if [[ -n "$submodules" ]]; then
    while IFS= read -r submodule_path; do
      [[ -z "$submodule_path" ]] && continue

      # Check if this submodule is in the changed files list
      if echo "$changed_files" | grep -qx "$submodule_path"; then
        echo "Detected change in submodule: $submodule_path" >&2

        # Check if any filter pattern could match files in this submodule
        if _could_match_patterns "$submodule_path" "${patterns[@]}"; then
          echo "Filter patterns may match files in submodule '$submodule_path', inspecting..." >&2

          # Configure git for private submodule access
          _configure_git_for_submodules

          # Get old and new submodule commits
          local commits
          commits=$(_get_submodule_commits "$submodule_path" "$prev_commit" "$current_commit")

          if [[ -n "$commits" ]]; then
            local old_sha new_sha
            old_sha=$(echo "$commits" | awk '{print $1}')
            new_sha=$(echo "$commits" | awk '{print $2}')

            # Get changed files within submodule
            local submodule_files
            submodule_files=$(_get_submodule_changed_files "$submodule_path" "$old_sha" "$new_sha" || echo "")

            if [[ -n "$submodule_files" ]]; then
              echo "Files changed in submodule '$submodule_path':" >&2
              echo "$submodule_files" | while read -r file; do
                [[ -n "$file" ]] && echo "  $file" >&2
              done
              # Add submodule files to the list (replacing the submodule path entry)
              all_changed_files=$(echo "$all_changed_files" | grep -vx "$submodule_path" || true)
              all_changed_files="${all_changed_files}"$'\n'"${submodule_files}"
            fi
          fi
        else
          echo "No filter patterns match submodule '$submodule_path', skipping inspection" >&2
        fi
      fi
    done <<< "$submodules"
  fi

  CHANGED_FILES="$all_changed_files"

  # Check if any changed file matches the patterns
  while IFS= read -r changed_file; do
    [[ -z "$changed_file" ]] && continue
    if _matches_patterns "$changed_file" "${patterns[@]}"; then
      CHANGES_DETECTED="true"
      echo "Changes detected: $CHANGES_DETECTED" >&2
      export CHANGES_DETECTED CHANGED_FILES
      return 0
    fi
  done <<< "$all_changed_files"

  echo "No matching changes detected" >&2
  export CHANGES_DETECTED CHANGED_FILES
  return 0
}
