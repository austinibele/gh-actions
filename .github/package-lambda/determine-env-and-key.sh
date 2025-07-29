#!/usr/bin/env bash
# determine-env-and-key.sh
# Purpose: Given a branch name, key prefix, and commit SHA, output the env tag, S3 prefix, and S3 key in key=value format.
# Usage: determine-env-and-key.sh <branch> <key_prefix> <sha>

set -euo pipefail

usage() { echo "Usage: $0 --branch <branch> --key-prefix <prefix> --sha <sha>" >&2; exit 1; }

BRANCH=""; KEY_PREFIX=""; SHA="";

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) BRANCH="$2"; shift 2 ;;
    --key-prefix) KEY_PREFIX="$2"; shift 2 ;;
    --sha) SHA="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$BRANCH" || -z "$KEY_PREFIX" || -z "$SHA" ]] && usage

if [[ "$BRANCH" == "main" ]]; then
  ENV_TAG="prod"
else
  ENV_TAG="dev"
fi

S3_PREFIX="${KEY_PREFIX}-${ENV_TAG}"
S3_KEY="${KEY_PREFIX}-${ENV_TAG}-${SHA}.zip"

echo "env_tag=${ENV_TAG}"
echo "s3_prefix=${S3_PREFIX}"
echo "s3_key=${S3_KEY}" 