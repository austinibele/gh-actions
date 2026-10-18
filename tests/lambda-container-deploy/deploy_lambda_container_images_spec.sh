#shellspec
# Tests for .github/lambda-container-deploy/deploy-lambda-container-images.sh.
# Runs in a temp working directory holding the tf-output.json fixture; stubs aws on PATH
# and appends every call to $AWS_CALL_LOG.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_UNDER_TEST="${SCRIPT_DIR}/../../.github/lambda-container-deploy/deploy-lambda-container-images.sh"

SSR_IMAGE="123456789012.dkr.ecr.us-east-1.amazonaws.com/ssr:abc123"
IMAGE_URIS='{"ssr":"'"$SSR_IMAGE"'"}'
EXPECTED_SSR='{"ssr":{"image_service_id":"ssr"}}'

# AWS_LAMBDA_MODE: successful | in-progress-then-successful | in-progress | failed
_make_aws_stub() {
  local stub_dir="$1"
  cat >"${stub_dir}/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$AWS_CALL_LOG"
case "$1 $2" in
  "lambda update-function-code")
    printf '%s\n' '{}'
    ;;
  "lambda get-function")
    polls="$(($(cat "$AWS_POLL_STATE") + 1))"
    printf '%s\n' "$polls" >"$AWS_POLL_STATE"
    case "$AWS_LAMBDA_MODE" in
      successful) printf '%s\t%s\n' Successful None ;;
      in-progress-then-successful)
        if [[ "$polls" -ge 2 ]]; then
          printf '%s\t%s\n' Successful None
        else
          printf '%s\t%s\n' InProgress None
        fi
        ;;
      in-progress) printf '%s\t%s\n' InProgress None ;;
      failed) printf '%s\t%s\n' Failed 'Image manifest not found' ;;
    esac
    ;;
  *)
    echo "unexpected aws call: $*" >&2
    exit 99
    ;;
esac
EOF
  chmod +x "${stub_dir}/aws"
}

_write_tf_output() {
  printf '%s\n' "$1" >"${workdir}/tf-output.json"
}

_metadata() {
  printf '{"app_deploy_metadata":{"value":{"lambda_functions":%s}}}' "$1"
}

_setup() {
  stub_dir=$(mktemp -d)
  workdir=$(mktemp -d)
  call_log=$(mktemp)
  poll_state=$(mktemp)
  printf '%s\n' 0 >"$poll_state"
  _make_aws_stub "$stub_dir"
}

# Runs the script in $workdir, prints the aws calls, keeps the script's exit status.
_run_script() {
  env \
    PATH="$stub_dir:$PATH" \
    AWS_CALL_LOG="$call_log" \
    AWS_POLL_STATE="$poll_state" \
    AWS_LAMBDA_MODE="${AWS_LAMBDA_MODE:-successful}" \
    DEPLOY_METADATA_OUTPUT="app_deploy_metadata" \
    IMAGE_URIS_JSON="$IMAGE_URIS" \
    LAMBDA_UPDATE_POLL_SECONDS=0 \
    LAMBDA_UPDATE_MAX_POLLS=3 \
    "$@" \
    bash -c 'cd "$1" || exit 98; bash "$SCRIPT_UNDER_TEST"; status=$?; echo "OPS=$(cut -d" " -f1-2 "$2" | tr "\n" "|")"; echo "CALLS<<$(cat "$2")>>"; exit "$status"' _ "$workdir" "$call_log"
}

Describe 'deploy-lambda-container-images.sh'
  BeforeEach '_setup'

  It 'fails when tf-output.json is missing from the working directory'
    When run _run_script REBUILT_SERVICE_IDS_JSON='["ssr"]' ENV_OR_INFRA_CHANGED=false EXPECTED_LAMBDA_FUNCTIONS_JSON="$EXPECTED_SSR"

    The status should equal 1
    The output should include "::error::tf-output.json not found"
    The output should include "CALLS<<>>"
  End

  It 'fails when the deploy metadata is empty but Lambdas are expected'
    _write_tf_output '{"other_output":{"value":"x"}}'

    When run _run_script REBUILT_SERVICE_IDS_JSON='["ssr"]' ENV_OR_INFRA_CHANGED=false EXPECTED_LAMBDA_FUNCTIONS_JSON="$EXPECTED_SSR"

    The status should equal 1
    The output should include "::error::Deploy metadata is empty but Lambda targets are expected"
  End

  It 'skips when the deploy metadata is empty and no Lambda is expected'
    _write_tf_output '{"app_deploy_metadata":{"value":null}}'

    When run _run_script REBUILT_SERVICE_IDS_JSON='["ssr"]' ENV_OR_INFRA_CHANGED=true EXPECTED_LAMBDA_FUNCTIONS_JSON='{}'

    The status should be success
    The output should include "Deploy metadata is empty; skipping lambda image updates"
    The output should include "CALLS<<>>"
  End

  It 'fails when an expected Lambda has a different image_service_id in the metadata'
    _write_tf_output "$(_metadata '{"ssr":{"function_name":"app-ssr","image_service_id":"ssr-legacy"}}')"

    When run _run_script REBUILT_SERVICE_IDS_JSON='["ssr"]' ENV_OR_INFRA_CHANGED=false EXPECTED_LAMBDA_FUNCTIONS_JSON="$EXPECTED_SSR"

    The status should equal 1
    The output should include "::error::Lambda 'ssr' image_service_id mismatch: expected 'ssr', got 'ssr-legacy'"
    The output should not include "update-function-code"
  End

  It 'skips a Lambda that was not rebuilt when env/infra is unchanged'
    _write_tf_output "$(_metadata '{"ssr":{"function_name":"app-ssr","image_service_id":"ssr"}}')"

    When run _run_script REBUILT_SERVICE_IDS_JSON='[]' ENV_OR_INFRA_CHANGED=false EXPECTED_LAMBDA_FUNCTIONS_JSON="$EXPECTED_SSR"

    The status should be success
    The output should include "Skip app-ssr (image service ssr not rebuilt, env/infra unchanged)"
    The output should not include "update-function-code"
  End

  It 'updates a rebuilt Lambda and polls get-function until the update is Successful'
    _write_tf_output "$(_metadata '{"ssr":{"function_name":"app-ssr","image_service_id":"ssr"}}')"

    When run _run_script AWS_LAMBDA_MODE=in-progress-then-successful REBUILT_SERVICE_IDS_JSON='["ssr"]' ENV_OR_INFRA_CHANGED=false EXPECTED_LAMBDA_FUNCTIONS_JSON="$EXPECTED_SSR"

    The status should be success
    The output should include "Updating lambda app-ssr with image ${SSR_IMAGE}"
    The output should include "lambda update-function-code --function-name app-ssr --image-uri ${SSR_IMAGE}"
    The output should include "OPS=lambda update-function-code|lambda get-function|lambda get-function|"
    The output should include "Lambda app-ssr update finished: Successful"
  End

  It 'fails when get-function reports the update Failed'
    _write_tf_output "$(_metadata '{"ssr":{"function_name":"app-ssr","image_service_id":"ssr"}}')"

    When run _run_script AWS_LAMBDA_MODE=failed REBUILT_SERVICE_IDS_JSON='["ssr"]' ENV_OR_INFRA_CHANGED=false EXPECTED_LAMBDA_FUNCTIONS_JSON="$EXPECTED_SSR"

    The status should equal 1
    The output should include "::error::Lambda app-ssr update failed: Image manifest not found"
  End

  It 'fails when the update is still in progress after update-max-polls checks'
    _write_tf_output "$(_metadata '{"ssr":{"function_name":"app-ssr","image_service_id":"ssr"}}')"

    When run _run_script AWS_LAMBDA_MODE=in-progress REBUILT_SERVICE_IDS_JSON='["ssr"]' ENV_OR_INFRA_CHANGED=false EXPECTED_LAMBDA_FUNCTIONS_JSON="$EXPECTED_SSR"

    The status should equal 1
    The output should include "OPS=lambda update-function-code|lambda get-function|lambda get-function|lambda get-function|"
    The output should include "::error::Lambda app-ssr update did not finish after 3 checks (last status: 'InProgress')"
  End

  It 'maps a legacy single lambda entry onto the one expected mapping and updates it'
    _write_tf_output '{"app_deploy_metadata":{"value":{"lambda":{"function_name":"app-ssr"}}}}'

    When run _run_script REBUILT_SERVICE_IDS_JSON='["ssr"]' ENV_OR_INFRA_CHANGED=false EXPECTED_LAMBDA_FUNCTIONS_JSON="$EXPECTED_SSR"

    The status should be success
    The output should include "Using legacy lambda deploy metadata with the configured Lambda mapping"
    The output should include "lambda update-function-code --function-name app-ssr --image-uri ${SSR_IMAGE}"
    The output should include "Lambda app-ssr update finished: Successful"
  End

  It 'on an env/infra change updates the Lambdas it owns and skips one another pipeline builds'
    _write_tf_output "$(_metadata '{"media":{"function_name":"app-media","image_service_id":"media-processor"},"ssr":{"function_name":"app-ssr","image_service_id":"ssr"}}')"

    When run _run_script REBUILT_SERVICE_IDS_JSON='[]' ENV_OR_INFRA_CHANGED=true EXPECTED_LAMBDA_FUNCTIONS_JSON="$EXPECTED_SSR"

    The status should be success
    The output should include "Skip app-media (image service media-processor is built and deployed by another pipeline)"
    The output should include "OPS=lambda update-function-code|lambda get-function|"
    The output should include "lambda update-function-code --function-name app-ssr"
    The output should not include "update-function-code --function-name app-media"
  End
End
