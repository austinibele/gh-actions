#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/.github/package-lambda/decide.sh"
  STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_DIR" "$BATS_TEST_DIRNAME/.tmp-git-template"
  GIT_WORK="$BATS_TEST_DIRNAME/.tmp-git"
  PATH="$STUB_DIR:$PATH"

  cat >"$STUB_DIR/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != "s3" || "${2:-}" != "cp" ]]; then
  echo "unexpected aws $*" >&2
  exit 1
fi
src="$3"
dst="${4:-}"
if [[ "$src" != s3://* ]]; then
  echo "unexpected upload $*" >&2
  exit 1
fi
case "$src" in
  *missing.json)
    exit 1
    ;;
  *failure.json)
    printf '%s\n' '{"status":"failure","last_success_sha":"deadbeef"}' >"$dst"
    exit 0
    ;;
  *success.json)
    printf '%s\n' "{\"status\":\"success\",\"last_success_sha\":\"${LEDGER_STUB_LAST_SUCCESS_SHA:-deadbeef}\"}" >"$dst"
    exit 0
    ;;
  *)
    echo "unknown ledger key $src" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$STUB_DIR/aws"

  export ENV="prod"
  export S3_BUCKET="crm-lambda-zips-prod"
  export LEDGER_PREFIX="build-ledger/"
  export FILTER_PATTERNS='["src/**"]'
  unset FORCE_BUILD
}

teardown() {
  rm -rf "$BATS_TEST_DIRNAME/.tmp-git" "$BATS_TEST_DIRNAME/.tmp-git-template"
}

_init_git_repo() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q --template="$BATS_TEST_DIRNAME/.tmp-git-template"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" config user.name "test"
}

@test "ledger missing returns ledger_missing" {
  export ARTIFACT_ID="missing"
  export GITHUB_SHA="abc123"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"should_build=true"* ]]
  [[ "$output" == *"reason=ledger_missing"* ]]
}

@test "ledger status failure returns ledger_failed" {
  export ARTIFACT_ID="failure"
  export GITHUB_SHA="abc123"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"should_build=true"* ]]
  [[ "$output" == *"reason=ledger_failed"* ]]
}

@test "ledger success and matching change since last_success_sha returns source_changed" {
  repo="$GIT_WORK/src-changed"
  _init_git_repo "$repo"
  echo "init" >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm init
  first="$(git -C "$repo" rev-parse HEAD)"
  mkdir -p "$repo/src"
  echo "fn" >"$repo/src/handler.py"
  git -C "$repo" add src/handler.py
  git -C "$repo" commit -qm change
  head="$(git -C "$repo" rev-parse HEAD)"

  export ARTIFACT_ID="success"
  export LEDGER_STUB_LAST_SUCCESS_SHA="$first"
  export GITHUB_SHA="$head"
  run bash -c "cd '$repo' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"should_build=true"* ]]
  [[ "$output" == *"reason=source_changed"* ]]
  [[ "$output" == *"last_success_sha=$first"* ]]
}

@test "ledger success and no matching change returns no_changes" {
  repo="$GIT_WORK/no-change"
  _init_git_repo "$repo"
  echo "init" >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm init
  first="$(git -C "$repo" rev-parse HEAD)"
  echo "docs" >"$repo/NOTES.md"
  git -C "$repo" add NOTES.md
  git -C "$repo" commit -qm docs
  head="$(git -C "$repo" rev-parse HEAD)"

  export ARTIFACT_ID="success"
  export LEDGER_STUB_LAST_SUCCESS_SHA="$first"
  export GITHUB_SHA="$head"
  run bash -c "cd '$repo' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"should_build=false"* ]]
  [[ "$output" == *"reason=no_changes"* ]]
  [[ "$output" == *"last_success_sha=$first"* ]]
}

@test "FORCE_BUILD=true returns forced" {
  export ARTIFACT_ID="success"
  export FORCE_BUILD="true"
  export GITHUB_SHA="abc123"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"should_build=true"* ]]
  [[ "$output" == *"reason=forced"* ]]
}

@test "bare FILTER_PATTERNS string covers source_changed and no_changes" {
  export FILTER_PATTERNS='src/**'

  repo="$GIT_WORK/bare-src-changed"
  _init_git_repo "$repo"
  echo "init" >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm init
  first="$(git -C "$repo" rev-parse HEAD)"
  mkdir -p "$repo/src"
  echo "fn" >"$repo/src/handler.py"
  git -C "$repo" add src/handler.py
  git -C "$repo" commit -qm change
  head="$(git -C "$repo" rev-parse HEAD)"

  export ARTIFACT_ID="success"
  export LEDGER_STUB_LAST_SUCCESS_SHA="$first"
  export GITHUB_SHA="$head"
  run bash -c "cd '$repo' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"should_build=true"* ]]
  [[ "$output" == *"reason=source_changed"* ]]

  repo="$GIT_WORK/bare-no-change"
  _init_git_repo "$repo"
  echo "init" >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm init
  first="$(git -C "$repo" rev-parse HEAD)"
  echo "docs" >"$repo/NOTES.md"
  git -C "$repo" add NOTES.md
  git -C "$repo" commit -qm docs
  head="$(git -C "$repo" rev-parse HEAD)"

  export LEDGER_STUB_LAST_SUCCESS_SHA="$first"
  export GITHUB_SHA="$head"
  run bash -c "cd '$repo' && bash '$SCRIPT'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"should_build=false"* ]]
  [[ "$output" == *"reason=no_changes"* ]]
}

@test "changed_files is written to GITHUB_OUTPUT" {
  export ARTIFACT_ID="missing"
  export GITHUB_SHA="abc123"
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github_output"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q "changed_files" "$GITHUB_OUTPUT"
}
