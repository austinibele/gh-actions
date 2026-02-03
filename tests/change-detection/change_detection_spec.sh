#shellspec
# Tests for lib/change-detection.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_UNDER_TEST="${SCRIPT_DIR}/../../lib/change-detection.sh"

# Source common test helpers
. "${SCRIPT_DIR}/../helpers/common.sh"

Describe 'change-detection.sh::detect_changes'
  Include "$SCRIPT_UNDER_TEST"

  It 'sets CHANGES_DETECTED=true when no filter pattern provided'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      detect_changes ""
      echo "$CHANGES_DETECTED"
    '
    The output should equal "true"
    The stderr should include "Detecting changes..."
    The stderr should include "No filter pattern provided, assuming changes"
  End

  It 'detects changes when a diffed file matches the pattern'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_git_stub "$stub_dir" "src/app/main.ts"
      export GITHUB_EVENT_BEFORE=abc GITHUB_SHA=def
      detect_changes "[\"src/**\"]"
      echo "$CHANGES_DETECTED"
    '
    The output should equal "true"
    The stderr should include "Detecting changes..."
    The stderr should include "Comparing commits: abc...def"
    The stderr should include "Changed files:"
    The stderr should include "  src/app/main.ts"
    The stderr should include "Filter patterns:"
    The stderr should include "  src/**"
    The stderr should include "File 'src/app/main.ts' matches pattern 'src/**'"
  End

  It 'detects no changes when files do not match pattern'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_git_stub "$stub_dir" "docs/README.md"
      export GITHUB_EVENT_BEFORE=abc GITHUB_SHA=def
      detect_changes "[\"src/**\"]"
      echo "$CHANGES_DETECTED"
    '
    The output should equal "false"
    The stderr should include "Detecting changes..."
    The stderr should include "Changed files:"
    The stderr should include "  docs/README.md"
    The stderr should include "No matching changes detected"
  End

  It 'does not match frontend file against backend/** pattern'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_git_stub "$stub_dir" "myvisa/frontend/.prettierignore"
      export GITHUB_EVENT_BEFORE=abc GITHUB_SHA=def
      detect_changes "[\"myvisa/backend/**\"]"
      echo "$CHANGES_DETECTED"
    '
    The output should equal "false"
    The stderr should include "Detecting changes..."
    The stderr should include "  myvisa/frontend/.prettierignore"
    The stderr should include "No matching changes detected"
  End

  It 'detects changes for files directly in src/ with src/** pattern'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_git_stub "$stub_dir" "src/main.py"
      export GITHUB_EVENT_BEFORE=abc GITHUB_SHA=def
      detect_changes "[\"src/**\"]"
      echo "$CHANGES_DETECTED"
    '
    The output should equal "true"
    The stderr should include "File 'src/main.py' matches pattern 'src/**'"
  End

  It 'detects changes with exact file match'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_git_stub "$stub_dir" "package.json"
      export GITHUB_EVENT_BEFORE=abc GITHUB_SHA=def
      detect_changes "[\"package.json\"]"
      echo "$CHANGES_DETECTED"
    '
    The output should equal "true"
    The stderr should include "File 'package.json' matches pattern 'package.json'"
  End

  It 'detects changes when multiple patterns provided'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_git_stub "$stub_dir" "common/utils.ts"
      export GITHUB_EVENT_BEFORE=abc GITHUB_SHA=def
      detect_changes "[\"crm/backend/**\", \"common/**\", \"package.json\"]"
      echo "$CHANGES_DETECTED"
    '
    The output should equal "true"
    The stderr should include "File 'common/utils.ts' matches pattern 'common/**'"
  End

  It 'uses base_sha parameter when provided'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_git_stub "$stub_dir" "src/index.ts"
      export GITHUB_SHA=def
      detect_changes "[\"src/**\"]" "custom-base-sha"
      echo "$CHANGES_DETECTED"
    '
    The output should equal "true"
    The stderr should include "Comparing commits: custom-base-sha...def"
  End

  It 'sets CHANGED_FILES with the list of changed files'
    When run bash -c '
      source "$SCRIPT_UNDER_TEST"
      source "'"${SCRIPT_DIR}"'/../helpers/common.sh"
      stub_dir=$(mktemp -d)
      PATH="$stub_dir:$PATH"
      create_git_stub "$stub_dir" "src/a.ts
src/b.ts"
      export GITHUB_EVENT_BEFORE=abc GITHUB_SHA=def
      detect_changes "[\"src/**\"]"
      echo "$CHANGED_FILES"
    '
    The output should include "src/a.ts"
    The output should include "src/b.ts"
  End
End
