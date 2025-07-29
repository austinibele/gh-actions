#!/usr/bin/env bash
# Validates that every build-arg provided to the build workflow is declared in the Dockerfile.
# Usage: validate-build-args.sh <dockerfile-path> <build-args-multiline-string>
set -euo pipefail

usage() {
  echo "Usage: $0 --dockerfile <path> [--build-args <multiline-string>]" >&2
  exit 1
}

DOCKERFILE_PATH=""
BUILD_ARGS_INPUT=""

# Parse named options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dockerfile)
      DOCKERFILE_PATH="$2"; shift 2 ;;
    --build-args)
      BUILD_ARGS_INPUT="$2"; shift 2 ;;
    *) usage ;;
  esac
done

# Validate required argument
if [[ -z "$DOCKERFILE_PATH" ]]; then
  echo "Error: --dockerfile is required" >&2
  usage
fi

# If no build arguments were supplied, there is nothing to validate.
if [[ -z "${BUILD_ARGS_INPUT}" ]]; then
  echo "No build arguments provided; skipping validation."
  exit 0
fi

if [[ ! -f "${DOCKERFILE_PATH}" ]]; then
  echo "Dockerfile not found at path: ${DOCKERFILE_PATH}" >&2
  exit 1
fi

# Iterate over each non-empty line in the build args input.
while IFS= read -r line; do
  [[ -z "${line}" ]] && continue  # skip blank lines

  # Extract the argument name (strip everything after the first '=')
  ARG_NAME="${line%%=*}"

  # Verify the Dockerfile declares this ARG.
  if ! grep -Eiq "^ARG[[:space:]]+${ARG_NAME}([[:space:]]|=|$)" "${DOCKERFILE_PATH}"; then
    echo "Error: Build argument '${ARG_NAME}' is not defined in Dockerfile '${DOCKERFILE_PATH}'." >&2
    exit 1
  fi

done <<< "${BUILD_ARGS_INPUT}"

echo "All build arguments are declared in the Dockerfile." 