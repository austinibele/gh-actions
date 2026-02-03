#shellspec
# Tests for lib/github.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_UNDER_TEST="${SCRIPT_DIR}/../../lib/github.sh"

# Source common test helpers
. "${SCRIPT_DIR}/../helpers/common.sh"

Describe 'github.sh::check_previous_run'
  Include "$SCRIPT_UNDER_TEST"

  It 'returns error when job_pattern not provided'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      check_previous_run "" 2>&1
    '
    The output should include "job_pattern parameter is required"
    The status should be failure
  End

  It 'sets PREVIOUS_FAILED=false when gh CLI not available'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      # Create stub path without gh
      stub_dir=$(mktemp -d)
      PATH="$stub_dir"
      export GITHUB_REPOSITORY="foo/bar"
      export GITHUB_REF_NAME="main"
      export GITHUB_RUN_ID=100
      export GH_TOKEN="test-token"
      check_previous_run "build-frontend"
      echo "$PREVIOUS_FAILED"
    '
    The output should equal "false"
    The stderr should include "gh CLI not available"
  End

  It 'sets PREVIOUS_FAILED=false when no GitHub token available'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_gh_stub_no_runs "$stub_dir"
      export GITHUB_REPOSITORY="foo/bar"
      export GITHUB_REF_NAME="main"
      export GITHUB_RUN_ID=100
      unset GH_TOKEN GITHUB_TOKEN PAT
      check_previous_run "build-frontend"
      echo "$PREVIOUS_FAILED"
    '
    The output should equal "false"
    The stderr should include "No GitHub token available"
  End

  It 'sets PREVIOUS_FAILED=false when missing GitHub environment variables'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_gh_stub_no_runs "$stub_dir"
      export GH_TOKEN="test-token"
      unset GITHUB_REPOSITORY GITHUB_REF_NAME GITHUB_RUN_ID
      check_previous_run "build-frontend"
      echo "$PREVIOUS_FAILED"
    '
    The output should equal "false"
    The stderr should include "Missing GitHub environment variables"
  End

  It 'sets PREVIOUS_FAILED=false when no previous runs exist'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_gh_stub_no_runs "$stub_dir"
      export GITHUB_REPOSITORY="foo/bar"
      export GITHUB_REF_NAME="main"
      export GITHUB_RUN_ID=100
      export GH_TOKEN="test-token"
      check_previous_run "build-frontend"
      echo "$PREVIOUS_FAILED"
    '
    The output should equal "false"
    The stderr should include "Checking previous run status..."
    The stderr should include "Checking workflow runs for repository: foo/bar, branch: main"
    The stderr should include "No previous workflow runs found"
  End

  It 'sets PREVIOUS_FAILED=true when previous run failed'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_gh_stub_previous_failed "$stub_dir" "12345"
      export GITHUB_REPOSITORY="foo/bar"
      export GITHUB_REF_NAME="main"
      export GITHUB_RUN_ID=100
      export GH_TOKEN="test-token"
      check_previous_run "build-frontend"
      echo "$PREVIOUS_FAILED"
    '
    The output should equal "true"
    The stderr should include "Previous run failed"
  End

  It 'sets PREVIOUS_FAILED=false when previous run succeeded'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_gh_stub_previous_success "$stub_dir" "12345"
      export GITHUB_REPOSITORY="foo/bar"
      export GITHUB_REF_NAME="main"
      export GITHUB_RUN_ID=100
      export GH_TOKEN="test-token"
      check_previous_run "build-frontend"
      echo "$PREVIOUS_FAILED"
    '
    The output should equal "false"
    The stderr should include "Previous run succeeded"
  End
End
