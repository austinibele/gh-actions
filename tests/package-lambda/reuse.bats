#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SCRIPT="$REPO_ROOT/.github/package-lambda/reuse.sh"
  STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_DIR"
  PATH="$STUB_DIR:$PATH"

  cat >"$STUB_DIR/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" != "s3api" || "${2:-}" != "head-object" ]]; then
  echo "unexpected aws $*" >&2
  exit 1
fi
case "${HEAD_OBJECT_STUB:-}" in
  hit)
    echo '{"ContentLength":1}'
    exit 0
    ;;
  not_found)
    echo "An error occurred (404) when calling the HeadObject operation: Not Found" >&2
    exit 1
    ;;
  access_denied)
    echo "An error occurred (AccessDenied) when calling the HeadObject operation: Access Denied" >&2
    exit 255
    ;;
  *)
    echo "HEAD_OBJECT_STUB unset" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$STUB_DIR/aws"

  export KEY_PREFIX="mylambda"
  export S3_BUCKET="crm-lambda-zips-prod"
  export BRANCH="internal"
  export LAST_SUCCESS_SHA="deadbeef"
  export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github_output"
  : >"$GITHUB_OUTPUT"
}

@test "empty LAST_SUCCESS_SHA exits 1" {
  export LAST_SUCCESS_SHA=""
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"last_success_sha is empty"* ]]
}

@test "head-object not-found is reuse_miss" {
  export HEAD_OBJECT_STUB="not_found"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hit=false"* ]]
  [[ "$output" == *"reason=reuse_miss"* ]]
  grep -q "reason=reuse_miss" "$GITHUB_OUTPUT"
}

@test "head-object AccessDenied exits 1" {
  export HEAD_OBJECT_STUB="access_denied"
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"AccessDenied"* ]]
}

@test "head-object success is a hit" {
  export HEAD_OBJECT_STUB="hit"
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hit=true"* ]]
  [[ "$output" == *"s3_key=mylambda-dev-deadbeef.zip"* ]]
  grep -q "hit=true" "$GITHUB_OUTPUT"
}
