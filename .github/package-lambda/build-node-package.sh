#!/usr/bin/env bash
# build-node-package.sh
# Purpose: Install the pnpm workspace dependency closure for a Node Lambda
# build package, then run its build:lambda script and verify the bundle
# it must produce.
#
# Contract for BUILD_DIRECTORY: a pnpm workspace package with a
# "build:lambda" script that writes a self-contained bundle (every
# dependency inlined, e.g. an esbuild --bundle build) to
# "<BUILD_DIRECTORY>/dist/lambda/", which package-lambda then zips flat.
#
# Runs from the repo root (the composite action's default working
# directory) so the pnpm workspace filter resolves.
#
# Environment (required): BUILD_DIRECTORY
# Environment (optional): NODE_AUTH_TOKEN (private @scope registry auth,
#   consumed by the workspace root .npmrc)
set -euo pipefail

if [[ -z "${BUILD_DIRECTORY:-}" ]]; then
  echo "Error: BUILD_DIRECTORY must be set" >&2
  exit 1
fi

PACKAGE_JSON="${BUILD_DIRECTORY}/package.json"
if [[ ! -f "$PACKAGE_JSON" ]]; then
  echo "Error: no package.json at $PACKAGE_JSON" >&2
  exit 1
fi

PACKAGE_NAME=$(jq -r '.name // empty' "$PACKAGE_JSON")
if [[ -z "$PACKAGE_NAME" ]]; then
  echo "Error: $PACKAGE_JSON has no \"name\" field" >&2
  exit 1
fi

if ! jq -e '.scripts["build:lambda"] // empty' "$PACKAGE_JSON" >/dev/null 2>&1; then
  echo "Error: $PACKAGE_JSON has no \"build:lambda\" script" >&2
  exit 1
fi

echo "Installing workspace dependencies for ${PACKAGE_NAME}..."
pnpm install --filter "${PACKAGE_NAME}..." --frozen-lockfile

echo "Building Lambda bundle for ${PACKAGE_NAME}..."
pnpm --dir "$BUILD_DIRECTORY" run build:lambda

BUNDLE_DIR="${BUILD_DIRECTORY}/dist/lambda"
if [[ ! -d "$BUNDLE_DIR" ]] || [[ -z "$(ls -A "$BUNDLE_DIR" 2>/dev/null)" ]]; then
  echo "Error: $BUNDLE_DIR is missing or empty after build:lambda" >&2
  exit 1
fi

echo "Lambda bundle ready at $BUNDLE_DIR"
