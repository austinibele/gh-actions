#shellspec
# Tests for lib/ledger.sh functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_UNDER_TEST="${SCRIPT_DIR}/../../lib/ledger.sh"

# Source common test helpers
. "${SCRIPT_DIR}/../helpers/common.sh"

Describe 'ledger.sh::ledger_check'
  Include "$SCRIPT_UNDER_TEST"

  It 'returns LEDGER_SHOULD_BUILD=true when ledger file is missing'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    create_aws_stub "$stub_dir"

    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_aws_stub "$stub_dir"
      ledger_check "missing" "cafebabe" "dummy-bucket" "dev"
      echo "$LEDGER_SHOULD_BUILD"
    '
    The output should equal "true"
  End

  It 'returns LEDGER_SHOULD_BUILD=true when status is failure'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_aws_stub "$stub_dir"
      ledger_check "failure" "cafebabe" "dummy-bucket" "dev"
      echo "$LEDGER_SHOULD_BUILD"
    '
    The output should equal "true"
  End

  It 'returns LEDGER_SHOULD_BUILD=true when status is building'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_aws_stub "$stub_dir"
      ledger_check "building" "cafebabe" "dummy-bucket" "dev"
      echo "$LEDGER_SHOULD_BUILD"
    '
    The output should equal "true"
  End

  It 'returns LEDGER_SHOULD_BUILD=false when status is success (defers to downstream)'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_aws_stub "$stub_dir"
      ledger_check "oldsha" "cafebabe" "dummy-bucket" "dev"
      echo "$LEDGER_SHOULD_BUILD"
    '
    The output should equal "false"
  End

  It 'returns LEDGER_SHOULD_BUILD=false when SHA matches and status success'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_aws_stub "$stub_dir"
      ledger_check "samesha" "cafebabe" "dummy-bucket" "dev"
      echo "$LEDGER_SHOULD_BUILD"
    '
    The output should equal "false"
  End

  It 'sets LEDGER_LAST_SUCCESS_SHA from ledger file'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_aws_stub "$stub_dir"
      ledger_check "oldsha" "cafebabe" "dummy-bucket" "dev"
      echo "$LEDGER_LAST_SUCCESS_SHA"
    '
    The output should equal "deadbeef"
  End

  It 'sets LEDGER_FILE_EXISTS=false when ledger file is missing'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_aws_stub "$stub_dir"
      ledger_check "missing" "cafebabe" "dummy-bucket" "dev"
      echo "$LEDGER_FILE_EXISTS"
    '
    The output should equal "false"
  End

  It 'sets LEDGER_FILE_EXISTS=true when ledger file exists with failure status'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_aws_stub "$stub_dir"
      ledger_check "failure" "cafebabe" "dummy-bucket" "dev"
      echo "$LEDGER_FILE_EXISTS"
    '
    The output should equal "true"
  End

  It 'sets LEDGER_FILE_EXISTS=true when ledger file exists with success status'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_aws_stub "$stub_dir"
      ledger_check "oldsha" "cafebabe" "dummy-bucket" "dev"
      echo "$LEDGER_FILE_EXISTS"
    '
    The output should equal "true"
  End

  It 'returns error when bucket is not provided'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      unset LEDGER_BUCKET
      unset ENV
      ledger_check "test" "sha123" "" "" 2>&1
    '
    The output should include "S3 bucket must be provided"
    The status should be failure
  End

  It 'returns error when env is not provided'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      unset ENV
      ledger_check "test" "sha123" "dummy-bucket" "" 2>&1
    '
    The output should include "env must be provided"
    The status should be failure
  End

  It 'uses LEDGER_BUCKET and ENV env vars when args not provided'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_aws_stub "$stub_dir"
      export LEDGER_BUCKET="dummy-bucket"
      export ENV="dev"
      ledger_check "samesha" "cafebabe"
      echo "$LEDGER_SHOULD_BUILD"
    '
    The output should equal "false"
  End
End

Describe 'ledger.sh::ledger_write'
  Include "$SCRIPT_UNDER_TEST"

  It 'writes status record to S3'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_aws_stub "$stub_dir"
      ledger_write "my-artifact" "success" "abc123" "dummy-bucket" "dev"
      echo "success"
    '
    The output should equal "success"
    The status should be success
  End

  It 'returns error when bucket is not provided'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      unset LEDGER_BUCKET
      unset ENV
      ledger_write "test" "success" "sha123" "" "" 2>&1
    '
    The output should include "S3 bucket must be provided"
    The status should be failure
  End

  It 'returns error when env is not provided'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      unset ENV
      ledger_write "test" "success" "sha123" "dummy-bucket" "" 2>&1
    '
    The output should include "env must be provided"
    The status should be failure
  End

  Describe 'last_success preservation'
    It 'building write preserves prior last_success_sha and last_success_ts'
      When run bash -c '
        source "$SCRIPT_UNDER_TEST"
        stub_dir=$(mktemp -d)
        upload_log=$(mktemp)
        PATH="$stub_dir:$PATH"
        cat >"${stub_dir}/aws" <<EOS
#!/usr/bin/env bash
set -euo pipefail
cmd="\$1"; shift
subcmd="\$1"; shift
src="\$1"; dst="\$2"
if [[ "\$src" == s3://* ]]; then
  case "\$src" in
    *with-history.json)
      cat <<EOF >"\$dst"
{"status":"success","last_success_sha":"deadbeef","last_success_ts":"2024-01-01T00:00:00Z"}
EOF
      exit 0;;
    *)
      exit 1;;
  esac
else
  cat > "${upload_log}"
fi
EOS
        chmod +x "${stub_dir}/aws"
        cat >"${stub_dir}/date" <<EOF
#!/usr/bin/env bash
echo "2024-06-01T12:00:00Z"
EOF
        chmod +x "${stub_dir}/date"
        ledger_write "with-history" "building" "newsha" "dummy-bucket" "dev"
        cat "$upload_log"
      '
      The status should be success
      The output should include '"status": "building"'
      The output should include '"last_success_sha": "deadbeef"'
      The output should include '"last_success_ts": "2024-01-01T00:00:00Z"'
    End

    It 'failure write preserves prior last_success_sha and last_success_ts'
      When run bash -c '
        source "$SCRIPT_UNDER_TEST"
        stub_dir=$(mktemp -d)
        upload_log=$(mktemp)
        PATH="$stub_dir:$PATH"
        cat >"${stub_dir}/aws" <<EOS
#!/usr/bin/env bash
set -euo pipefail
cmd="\$1"; shift
subcmd="\$1"; shift
src="\$1"; dst="\$2"
if [[ "\$src" == s3://* ]]; then
  case "\$src" in
    *with-history.json)
      cat <<EOF >"\$dst"
{"status":"success","last_success_sha":"deadbeef","last_success_ts":"2024-01-01T00:00:00Z"}
EOF
      exit 0;;
    *)
      exit 1;;
  esac
else
  cat > "${upload_log}"
fi
EOS
        chmod +x "${stub_dir}/aws"
        cat >"${stub_dir}/date" <<EOF
#!/usr/bin/env bash
echo "2024-06-01T12:00:00Z"
EOF
        chmod +x "${stub_dir}/date"
        ledger_write "with-history" "failure" "newsha" "dummy-bucket" "dev"
        cat "$upload_log"
      '
      The status should be success
      The output should include '"status": "failure"'
      The output should include '"last_success_sha": "deadbeef"'
      The output should include '"last_success_ts": "2024-01-01T00:00:00Z"'
    End

    It 'success write overwrites last_success_sha and last_success_ts'
      When run bash -c '
        source "$SCRIPT_UNDER_TEST"
        stub_dir=$(mktemp -d)
        upload_log=$(mktemp)
        PATH="$stub_dir:$PATH"
        cat >"${stub_dir}/aws" <<EOS
#!/usr/bin/env bash
set -euo pipefail
cmd="\$1"; shift
subcmd="\$1"; shift
src="\$1"; dst="\$2"
if [[ "\$src" == s3://* ]]; then
  case "\$src" in
    *with-history.json)
      cat <<EOF >"\$dst"
{"status":"success","last_success_sha":"deadbeef","last_success_ts":"2024-01-01T00:00:00Z"}
EOF
      exit 0;;
    *)
      exit 1;;
  esac
else
  cat > "${upload_log}"
fi
EOS
        chmod +x "${stub_dir}/aws"
        cat >"${stub_dir}/date" <<EOF
#!/usr/bin/env bash
echo "2024-06-01T12:00:00Z"
EOF
        chmod +x "${stub_dir}/date"
        ledger_write "with-history" "success" "newsha" "dummy-bucket" "dev"
        cat "$upload_log"
      '
      The status should be success
      The output should include '"status": "success"'
      The output should include '"last_success_sha": "newsha"'
      The output should include '"last_success_ts": "2024-06-01T12:00:00Z"'
      The output should not include '"last_success_sha": "deadbeef"'
    End
  End
End
