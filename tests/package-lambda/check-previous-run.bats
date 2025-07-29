#!/usr/bin/env bats

setup() {
  SCRIPT=".github/package-lambda/check-previous-run.sh"
  STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_DIR"
  PATH="$STUB_DIR:$PATH"

  cat >"$STUB_DIR/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "api" ]]; then
  shift
  endpoint="$1"; shift
  # Decide which fixture to output
  if [[ "$endpoint" == *"/jobs" ]]; then
    file="$JOBS_JSON"
  else
    file="$RUNS_JSON"
  fi
  content="$(cat "$file")"

  if [[ "$1" == "--jq" ]]; then
    shift
    jq_expr="$1"
    echo "$content" | jq -r "$jq_expr"
  else
    echo "$content"
  fi
fi
EOF
  chmod +x "$STUB_DIR/gh"
}

@test "previous run failure returns true" {
  export RUNS_JSON="$BATS_TEST_DIRNAME/fixtures/runs-failure.json"
  export JOBS_JSON="$BATS_TEST_DIRNAME/fixtures/jobs-failure.json"
  run bash "$SCRIPT" --repo myorg/myrepo --branch feature-foo --run-id 101 --key-prefix mylambda
  [ "$status" -eq 0 ]
  [[ "$output" == *"previous_failed=true"* ]]
}

@test "previous run success returns false" {
  export RUNS_JSON="$BATS_TEST_DIRNAME/fixtures/runs-success.json"
  export JOBS_JSON="$BATS_TEST_DIRNAME/fixtures/jobs-success.json"
  run bash "$SCRIPT" --repo myorg/myrepo --branch feature-foo --run-id 101 --key-prefix mylambda
  [ "$status" -eq 0 ]
  [[ "$output" == *"previous_failed=false"* ]]
}

@test "no previous run returns false" {
  export RUNS_JSON="$BATS_TEST_DIRNAME/fixtures/runs-none.json"
  export JOBS_JSON="$BATS_TEST_DIRNAME/fixtures/jobs-success.json"
  run bash "$SCRIPT" --repo myorg/myrepo --branch feature-foo --run-id 101 --key-prefix mylambda
  [ "$status" -eq 0 ]
  [[ "$output" == *"previous_failed=false"* ]]
} 