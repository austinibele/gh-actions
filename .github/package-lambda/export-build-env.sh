#!/usr/bin/env bash
# export-build-env.sh
# Purpose: Export environment variables from a JSON array with objects {"name":"FOO","value":"bar"}.
# Usage: source export-build-env.sh '<json-string>'

set -euo pipefail

usage() { echo "Usage: $0 --json '<json-array>'" >&2; exit 1; }

JSON_INPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_INPUT="$2"; shift 2 ;;
    *) usage ;;
  esac
done

# If invoked with 'source' and no arguments, allow reading JSON from env variable BUILD_ENV_JSON as fallback
if [[ -z "$JSON_INPUT" ]]; then
  JSON_INPUT="${BUILD_ENV_JSON:-}"
fi

# No JSON provided means nothing to export
if [[ -z "$JSON_INPUT" || "$JSON_INPUT" == "[]" ]]; then
  # If the script is being sourced, 'return' won't exit the parent shell.
  return 0 2>/dev/null || exit 0
fi

while IFS= read -r item; do
  NAME=$(echo "$item" | jq -r '.name')
  VALUE=$(echo "$item" | jq -r '.value')
  export "$NAME"="$VALUE"
done < <(echo "$JSON_INPUT" | jq -c '.[]') 