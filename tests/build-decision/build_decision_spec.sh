#shellspec
# Tests for build-decision.sh orchestration script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_UNDER_TEST="${SCRIPT_DIR}/../../.github/build-decision/build-decision.sh"

# Source common test helpers
. "${SCRIPT_DIR}/../helpers/common.sh"

Describe 'build-decision.sh'

  Describe 'FORCE_BUILD behavior'
    It 'outputs should_build=true and reason=forced when FORCE_BUILD=true'
      When run bash -c '
        export ARTIFACT_ID="test-artifact"
        export FILTER_PATTERNS="[]"
        export S3_BUCKET="test-bucket"
        export FORCE_BUILD="true"
        export GITHUB_OUTPUT=$(mktemp)
        bash "$SCRIPT_UNDER_TEST" 2>/dev/null
        grep "should_build" "$GITHUB_OUTPUT"
        grep "reason" "$GITHUB_OUTPUT"
      '
      The output should include "should_build=true"
      The output should include "reason=forced"
    End

    It 'outputs should_build=true when FORCE_BUILD=1'
      When run bash -c '
        export ARTIFACT_ID="test-artifact"
        export FILTER_PATTERNS="[]"
        export S3_BUCKET="test-bucket"
        export FORCE_BUILD="1"
        export GITHUB_OUTPUT=$(mktemp)
        bash "$SCRIPT_UNDER_TEST" 2>/dev/null
        grep "should_build" "$GITHUB_OUTPUT"
      '
      The output should include "should_build=true"
    End
  End

  Describe 'Ledger missing scenario'
    It 'outputs should_build=true and reason=ledger_missing when ledger file missing'
      When run bash -c '
        source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
        stub_dir=$(mktemp -d)
        PATH="$stub_dir:$PATH"
        create_aws_stub "$stub_dir"
        create_git_stub "$stub_dir" ""
        
        export ARTIFACT_ID="missing"
        export FILTER_PATTERNS="[\"src/**\"]"
        export S3_BUCKET="test-bucket"
        export CHECK_PREVIOUS_RUN="false"
        export GITHUB_OUTPUT=$(mktemp)
        export GITHUB_SHA="abc123"
        
        bash "$SCRIPT_UNDER_TEST" 2>/dev/null
        grep "should_build" "$GITHUB_OUTPUT"
        grep "reason" "$GITHUB_OUTPUT"
      '
      The output should include "should_build=true"
      The output should include "reason=ledger_missing"
    End
  End

  Describe 'Ledger failed scenario'
    It 'outputs should_build=true and reason=ledger_failed when ledger status is failure'
      When run bash -c '
        source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
        stub_dir=$(mktemp -d)
        PATH="$stub_dir:$PATH"
        create_aws_stub "$stub_dir"
        create_git_stub "$stub_dir" ""
        
        export ARTIFACT_ID="failure"
        export FILTER_PATTERNS="[\"src/**\"]"
        export S3_BUCKET="test-bucket"
        export CHECK_PREVIOUS_RUN="false"
        export GITHUB_OUTPUT=$(mktemp)
        export GITHUB_SHA="abc123"
        
        bash "$SCRIPT_UNDER_TEST" 2>/dev/null
        grep "should_build" "$GITHUB_OUTPUT"
        grep "reason" "$GITHUB_OUTPUT"
      '
      The output should include "should_build=true"
      The output should include "reason=ledger_failed"
    End

    It 'outputs reason=ledger_failed when ledger exists with failure but no last_success_sha'
      When run bash -c '
        source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
        stub_dir=$(mktemp -d)
        PATH="$stub_dir:$PATH"
        create_aws_stub "$stub_dir"
        create_git_stub "$stub_dir" ""
        
        export ARTIFACT_ID="failure-no-success"
        export FILTER_PATTERNS="[\"src/**\"]"
        export S3_BUCKET="test-bucket"
        export CHECK_PREVIOUS_RUN="false"
        export GITHUB_OUTPUT=$(mktemp)
        export GITHUB_SHA="abc123"
        
        bash "$SCRIPT_UNDER_TEST" 2>/dev/null
        grep "should_build" "$GITHUB_OUTPUT"
        grep "reason" "$GITHUB_OUTPUT"
      '
      The output should include "should_build=true"
      The output should include "reason=ledger_failed"
    End
  End

  Describe 'Source changed scenario'
    It 'outputs should_build=true and reason=source_changed when source files changed'
      When run bash -c '
        source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
        stub_dir=$(mktemp -d)
        PATH="$stub_dir:$PATH"
        create_aws_stub "$stub_dir"
        create_git_stub "$stub_dir" "src/main.ts"
        
        export ARTIFACT_ID="oldsha"
        export FILTER_PATTERNS="[\"src/**\"]"
        export S3_BUCKET="test-bucket"
        export CHECK_PREVIOUS_RUN="false"
        export GITHUB_OUTPUT=$(mktemp)
        export GITHUB_SHA="abc123"
        
        bash "$SCRIPT_UNDER_TEST" 2>/dev/null
        grep "should_build" "$GITHUB_OUTPUT"
        grep "reason" "$GITHUB_OUTPUT"
      '
      The output should include "should_build=true"
      The output should include "reason=source_changed"
    End
  End

  Describe 'No changes scenario'
    It 'outputs should_build=false and reason=no_changes when no changes detected'
      When run bash -c '
        source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
        stub_dir=$(mktemp -d)
        PATH="$stub_dir:$PATH"
        create_aws_stub "$stub_dir"
        create_git_stub "$stub_dir" "docs/README.md"
        create_gh_stub_no_runs "$stub_dir"
        
        export ARTIFACT_ID="oldsha"
        export FILTER_PATTERNS="[\"src/**\"]"
        export S3_BUCKET="test-bucket"
        export CHECK_PREVIOUS_RUN="false"
        export GITHUB_OUTPUT=$(mktemp)
        export GITHUB_SHA="abc123"
        
        bash "$SCRIPT_UNDER_TEST" 2>/dev/null
        grep "should_build" "$GITHUB_OUTPUT"
        grep "reason" "$GITHUB_OUTPUT"
      '
      The output should include "should_build=false"
      The output should include "reason=no_changes"
    End
  End

  Describe 'Previous failed scenario'
    It 'outputs should_build=true and reason=previous_failed when previous run failed'
      When run bash -c '
        source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
        stub_dir=$(mktemp -d)
        PATH="$stub_dir:$PATH"
        create_aws_stub "$stub_dir"
        create_git_stub "$stub_dir" "docs/README.md"
        create_gh_stub_previous_failed "$stub_dir" "12345"
        
        export ARTIFACT_ID="oldsha"
        export FILTER_PATTERNS="[\"src/**\"]"
        export S3_BUCKET="test-bucket"
        export CHECK_PREVIOUS_RUN="true"
        export JOB_PATTERN="build-test"
        export GITHUB_OUTPUT=$(mktemp)
        export GITHUB_SHA="abc123"
        export GITHUB_REPOSITORY="foo/bar"
        export GITHUB_REF_NAME="main"
        export GITHUB_RUN_ID="999"
        export GH_TOKEN="test-token"
        
        bash "$SCRIPT_UNDER_TEST" 2>/dev/null
        grep "should_build" "$GITHUB_OUTPUT"
        grep "reason" "$GITHUB_OUTPUT"
      '
      The output should include "should_build=true"
      The output should include "reason=previous_failed"
    End
  End

  Describe 'last_success_sha output'
    It 'outputs last_success_sha from ledger'
      When run bash -c '
        source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
        stub_dir=$(mktemp -d)
        PATH="$stub_dir:$PATH"
        create_aws_stub "$stub_dir"
        create_git_stub "$stub_dir" "docs/README.md"
        create_gh_stub_no_runs "$stub_dir"
        
        export ARTIFACT_ID="oldsha"
        export FILTER_PATTERNS="[\"src/**\"]"
        export S3_BUCKET="test-bucket"
        export CHECK_PREVIOUS_RUN="false"
        export GITHUB_OUTPUT=$(mktemp)
        export GITHUB_SHA="abc123"
        
        bash "$SCRIPT_UNDER_TEST" 2>/dev/null
        grep "last_success_sha" "$GITHUB_OUTPUT"
      '
      The output should include "last_success_sha=deadbeef"
    End
  End
End
