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
      ledger_check "missing" "cafebabe" "dummy-bucket"
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
      ledger_check "failure" "cafebabe" "dummy-bucket"
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
      ledger_check "building" "cafebabe" "dummy-bucket"
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
      ledger_check "oldsha" "cafebabe" "dummy-bucket"
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
      ledger_check "samesha" "cafebabe" "dummy-bucket"
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
      ledger_check "oldsha" "cafebabe" "dummy-bucket"
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
      ledger_check "missing" "cafebabe" "dummy-bucket"
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
      ledger_check "failure" "cafebabe" "dummy-bucket"
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
      ledger_check "oldsha" "cafebabe" "dummy-bucket"
      echo "$LEDGER_FILE_EXISTS"
    '
    The output should equal "true"
  End

  It 'returns error when bucket is not provided'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      unset LEDGER_BUCKET
      ledger_check "test" "sha123" "" 2>&1
    '
    The output should include "S3 bucket must be provided"
    The status should be failure
  End

  It 'uses LEDGER_BUCKET env var when bucket arg not provided'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_aws_stub "$stub_dir"
      export LEDGER_BUCKET="dummy-bucket"
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
      ledger_write "my-artifact" "success" "abc123" "dummy-bucket"
      echo "success"
    '
    The output should equal "success"
    The status should be success
  End

  It 'returns error when bucket is not provided'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      unset LEDGER_BUCKET
      ledger_write "test" "success" "sha123" "" 2>&1
    '
    The output should include "S3 bucket must be provided"
    The status should be failure
  End
End
