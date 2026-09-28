#!/usr/bin/env bash
# resolve-runtime.sh
# Purpose: Validate the package-lambda `runtime` input and resolve the
# version string to hand to actions/setup-python or actions/setup-node.
# Prints GITHUB_OUTPUT lines:
#   runtime=python|node
#   version=<resolved version>
# Exits 1 with a clear message for any other runtime value.
#
# Environment (required): RUNTIME
# Environment (optional): RUNTIME_VERSION, PYTHON_VERSION
set -euo pipefail

write_output() {
  local name="$1" value="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${name}=${value}" >> "$GITHUB_OUTPUT"
  fi
  echo "${name}=${value}"
}

case "${RUNTIME:-python}" in
  python)
    version="${RUNTIME_VERSION:-${PYTHON_VERSION:-3.12}}"
    write_output "runtime" "python"
    write_output "version" "$version"
    ;;
  node)
    version="${RUNTIME_VERSION:-22}"
    write_output "runtime" "node"
    write_output "version" "$version"
    ;;
  *)
    echo "Error: unsupported package-lambda runtime '${RUNTIME:-}' (expected 'python' or 'node')" >&2
    exit 1
    ;;
esac
