#!/usr/bin/env bash
# Common helpers for ShellSpec tests that verify shell utilities.

# Creates a temporary directory at the front of PATH for stub binaries.
# The directory is cleaned up on script exit.
create_stub_path() {
  _STUB_DIR="$(mktemp -d)"
  PATH="${_STUB_DIR}:$PATH"
  export PATH
  # shellcheck disable=SC2064
  trap 'rm -rf "${_STUB_DIR}"' EXIT
  echo "${_STUB_DIR}"
}

# Creates an aws CLI stub that simulates S3 operations.
# Usage: create_aws_stub <stub_dir>
# The stub handles:
#   - s3 cp s3://bucket/key /tmp/file (download)
#   - s3 cp - s3://bucket/key (upload)
# File naming conventions for test scenarios:
#   - *missing.json: returns 404 (exit 1)
#   - *failure.json: returns {"status":"failure","last_success_sha":"deadbeef"}
#   - *oldsha.json: returns {"status":"success","last_success_sha":"deadbeef"}
#   - *samesha.json: returns {"status":"success","last_success_sha":"cafebabe"}
#   - *building.json: returns {"status":"building","last_success_sha":"deadbeef"}
#   - *failure-no-success.json: returns {"status":"failure"} (no last_success_sha - first failed build)
create_aws_stub() {
  local stub_dir="$1"
  mkdir -p "${stub_dir}"

  cat >"${stub_dir}/aws" <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
cmd="$1"; shift
if [[ "$cmd" != "s3" ]]; then
  echo "unexpected cmd $cmd" >&2
  exit 1
fi
subcmd="$1"; shift
if [[ "$subcmd" != "cp" ]]; then
  echo "unexpected subcmd $subcmd" >&2
  exit 1
fi
src="$1" dst="$2"

# Download path (first arg starts with s3://)
if [[ "$src" == s3://* ]]; then
  key="$src"
  case "$key" in
    *missing.json)
      exit 1;;
    *failure.json)
      cat <<EOF >"$dst"
{"status":"failure","last_success_sha":"deadbeef"}
EOF
      exit 0;;
    *failure-no-success.json)
      cat <<EOF >"$dst"
{"status":"failure","last_attempt_sha":"abc123"}
EOF
      exit 0;;
    *oldsha.json)
      cat <<EOF >"$dst"
{"status":"success","last_success_sha":"deadbeef"}
EOF
      exit 0;;
    *samesha.json)
      cat <<EOF >"$dst"
{"status":"success","last_success_sha":"cafebabe"}
EOF
      exit 0;;
    *building.json)
      cat <<EOF >"$dst"
{"status":"building","last_success_sha":"deadbeef"}
EOF
      exit 0;;
    *)
      echo "unknown key $key" >&2
      exit 1;;
  esac
else
  # Upload path – just succeed (consume stdin)
  cat > /dev/null
fi
EOS
  chmod +x "${stub_dir}/aws"
}

# Creates a git stub for testing change detection.
# Usage: create_git_stub <stub_dir> <changed_files_list>
# changed_files_list: newline-separated list of files to return from git diff
create_git_stub() {
  local stub_dir="$1"
  local changed_files="$2"
  mkdir -p "${stub_dir}"

  cat >"${stub_dir}/git" <<EOS
#!/usr/bin/env bash
if [[ "\$1" == "diff" ]]; then
  cat <<'FILES'
${changed_files}
FILES
elif [[ "\$1" == "rev-parse" ]]; then
  echo "HEAD^"
elif [[ "\$1" == "cat-file" ]]; then
  exit 0
fi
EOS
  chmod +x "${stub_dir}/git"
}

# Creates a gh CLI stub that fails (for testing git fallback)
create_gh_stub_fail() {
  local stub_dir="$1"
  mkdir -p "${stub_dir}"

  cat >"${stub_dir}/gh" <<'EOS'
#!/usr/bin/env bash
exit 1
EOS
  chmod +x "${stub_dir}/gh"
}

# Creates a gh CLI stub that returns no runs
create_gh_stub_no_runs() {
  local stub_dir="$1"
  mkdir -p "${stub_dir}"

  cat >"${stub_dir}/gh" <<'EOS'
#!/usr/bin/env bash
# Return empty result for workflow runs query
echo ""
EOS
  chmod +x "${stub_dir}/gh"
}

# Creates a gh CLI stub that returns a failed previous run
# Usage: create_gh_stub_previous_failed <stub_dir> <run_id>
create_gh_stub_previous_failed() {
  local stub_dir="$1"
  local run_id="${2:-12345}"
  mkdir -p "${stub_dir}"

  cat >"${stub_dir}/gh" <<EOS
#!/usr/bin/env bash
if [[ "\$2" == *"/actions/runs" ]] && [[ "\$2" != *"/jobs" ]]; then
  echo "${run_id}"
elif [[ "\$2" == *"/jobs" ]]; then
  echo "failure"
fi
EOS
  chmod +x "${stub_dir}/gh"
}

# Creates a gh CLI stub that returns a successful previous run
# Usage: create_gh_stub_previous_success <stub_dir> <run_id>
create_gh_stub_previous_success() {
  local stub_dir="$1"
  local run_id="${2:-12345}"
  mkdir -p "${stub_dir}"

  cat >"${stub_dir}/gh" <<EOS
#!/usr/bin/env bash
if [[ "\$2" == *"/actions/runs" ]] && [[ "\$2" != *"/jobs" ]]; then
  echo "${run_id}"
elif [[ "\$2" == *"/jobs" ]]; then
  echo "success"
fi
EOS
  chmod +x "${stub_dir}/gh"
}

# Helper to resolve path to lib directory relative to test file
get_lib_path() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  echo "${script_dir}/../../lib"
}
