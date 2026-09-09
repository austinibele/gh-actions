#!/usr/bin/env bash
set -euo pipefail

: "${RELEASE_PATHS:?RELEASE_PATHS is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

last_release_commit="$(git log --grep='^chore(release): v' --max-count=1 --pretty=format:%H || true)"
if [[ -z "${last_release_commit}" ]]; then
  echo "No previous release bump commit found. Releasing."
  echo "should_release=true" >> "${GITHUB_OUTPUT}"
  exit 0
fi

read -r -a release_paths <<< "${RELEASE_PATHS}"
changed_files="$(git diff --name-only "${last_release_commit}..HEAD" -- "${release_paths[@]}")"
if [[ -z "${changed_files}" ]]; then
  echo "No releasable package changes since ${last_release_commit}. Skipping release."
  echo "should_release=false" >> "${GITHUB_OUTPUT}"
  exit 0
fi

echo "Releasable changes found:"
echo "${changed_files}"
echo "should_release=true" >> "${GITHUB_OUTPUT}"
