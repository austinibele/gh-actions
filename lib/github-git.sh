#!/usr/bin/env bash
# GitHub HTTPS authentication for one Git command, including its submodule children.
# Keep credentials out of URLs: newer libcurl strips URL userinfo, which Git 2.43
# mistakes for a redirect and consequently discards its authentication state.
set +x
set -euo pipefail

token="${PAT:-${NODE_AUTH_TOKEN:-}}"
if [[ -z "$token" ]]; then
  echo 'github-git.sh requires PAT or NODE_AUTH_TOKEN' >&2
  exit 1
fi

basic="$(printf 'x-access-token:%s' "$token" | base64 | tr -d '\r\n')"
if [[ "${GITHUB_ACTIONS:-}" == 'true' ]]; then
  printf '::add-mask::%s\n' "$basic"
fi
export GITHUB_GIT_AUTH_HEADER="AUTHORIZATION: basic $basic"

# Reset actions/checkout's inherited headers before adding ours. --config-env
# keeps the encoded token out of Git's command-line arguments and forwards the
# configuration to child Git processes without modifying any config file.
exec git -c http.https://github.com/.extraheader= \
  --config-env=http.https://github.com/.extraheader=GITHUB_GIT_AUTH_HEADER "$@"
