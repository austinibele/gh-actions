#!/usr/bin/env bash
set -euo pipefail

: "${PACKAGE_VERSION:?PACKAGE_VERSION is required}"
: "${REGISTRY_URL:?REGISTRY_URL is required}"
: "${NODE_AUTH_TOKEN:?NODE_AUTH_TOKEN is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

package_name="$(node -p "require('./package.json').name")"
version="${PACKAGE_VERSION}"
err_file="$(mktemp)"
out_file="$(mktemp)"

if npm view "${package_name}@${version}" version --registry "${REGISTRY_URL}" >"${out_file}" 2>"${err_file}"; then
  found_version="$(tr -d '[:space:]' <"${out_file}")"
  if [[ "${found_version}" == "${version}" ]]; then
    echo "Version already exists (${package_name}@${version}); skipping publish."
    echo "should_publish=false" >> "${GITHUB_OUTPUT}"
    exit 0
  fi
fi

if grep -qiE '404|not found' "${err_file}"; then
  echo "Version does not exist in registry yet."
elif [[ -s "${err_file}" ]]; then
  echo "npm view returned a non-404 response; continuing with publish attempt."
  cat "${err_file}"
fi

echo "should_publish=true" >> "${GITHUB_OUTPUT}"
