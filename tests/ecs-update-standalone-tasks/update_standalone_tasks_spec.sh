#shellspec
# Tests for .github/ecs-update-standalone-tasks/update-standalone-tasks.sh.
# Stubs aws on PATH; every call is appended to $AWS_CALL_LOG.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_UNDER_TEST="${SCRIPT_DIR}/../../.github/ecs-update-standalone-tasks/update-standalone-tasks.sh"

TD_PREFIX="arn:aws:ecs:us-east-1:123456789012:task-definition/web-cron"
WEB_IMAGE="123456789012.dkr.ecr.us-east-1.amazonaws.com/web:abc123"
IMAGE_URIS='{"web":"'"$WEB_IMAGE"'","api":"123456789012.dkr.ecr.us-east-1.amazonaws.com/api:def456"}'

# AWS_ECR_MODE: found | not-found. AWS_EB_VERIFIED_ARN: what the rule reports after put-targets.
_make_aws_stub() {
  local stub_dir="$1"
  cat >"${stub_dir}/aws" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"\$AWS_CALL_LOG"
case "\$1 \$2" in
  "ecr describe-images")
    if [[ "\${AWS_ECR_MODE:-found}" == "not-found" ]]; then
      echo "An error occurred (ImageNotFoundException) when calling the DescribeImages operation: image not found" >&2
      exit 254
    fi
    printf '%s\n' '{"imageDetails":[{}]}'
    ;;
  "ecs describe-task-definition")
    if [[ "\$*" == *"taskDefinition.status"* ]]; then
      printf '%s\n' ACTIVE
    else
      cat <<'JSON'
{"taskDefinitionArn":"${TD_PREFIX}:4","family":"web-cron","revision":4,"status":"ACTIVE","containerDefinitions":[{"name":"cron","image":"old-image"}],"requiresAttributes":[],"compatibilities":["FARGATE"],"registeredAt":"2026-01-01T00:00:00Z","registeredBy":"arn:aws:iam::123456789012:role/ci"}
JSON
    fi
    ;;
  "ecs register-task-definition")
    printf '%s\n' "${TD_PREFIX}:5"
    ;;
  "ecs list-task-definitions")
    printf '%s\t%s\t%s\n' "${TD_PREFIX}:3" "${TD_PREFIX}:4" "${TD_PREFIX}:5"
    ;;
  "ecs deregister-task-definition")
    printf '%s\n' "deregistered"
    ;;
  "events list-targets-by-rule")
    if [[ "\$*" == *"EcsParameters.TaskDefinitionArn"* ]]; then
      # The first ARN query verifies put-targets; later ones run before each deregistration.
      if [[ -n "\${AWS_EB_ARN_AFTER_VERIFY:-}" && "\$(grep -c 'EcsParameters.TaskDefinitionArn' "\$AWS_CALL_LOG")" -ge 2 ]]; then
        printf '%s\n' "\$AWS_EB_ARN_AFTER_VERIFY"
      else
        printf '%s\n' "\${AWS_EB_VERIFIED_ARN:-${TD_PREFIX}:5}"
      fi
    else
      printf '%s\n' '{"Id":"web-cron","Arn":"arn:aws:ecs:us-east-1:123456789012:cluster/app","EcsParameters":{"TaskDefinitionArn":"${TD_PREFIX}:4"}}'
    fi
    ;;
  "events put-targets")
    printf '%s\n' '{"FailedEntryCount":0,"FailedEntries":[]}'
    ;;
  *)
    echo "unexpected aws call: \$*" >&2
    exit 99
    ;;
esac
EOF
  chmod +x "${stub_dir}/aws"
}

_setup() {
  stub_dir=$(mktemp -d)
  workdir=$(mktemp -d)
  call_log=$(mktemp)
  _make_aws_stub "$stub_dir"
}

Describe 'update-standalone-tasks.sh'
  BeforeEach '_setup'

  It 'skips a task without task_definition_arn with a warning and makes no AWS call'
    When run env \
      PATH="$stub_dir:$PATH" \
      AWS_CALL_LOG="$call_log" \
      STANDALONE_TASKS_JSON='{"web_cron":{"image_service_id":"web"}}' \
      IMAGE_URIS_JSON="$IMAGE_URIS" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST" && echo "CALLS<<$(cat "'"$call_log"'")>>"'

    The status should be success
    The output should include "::warning::Standalone task web_cron is missing task_definition_arn or image_service_id; skipping"
    The output should include "CALLS<<>>"
  End

  It 'skips a task whose image service has no image URI with a warning'
    When run env \
      PATH="$stub_dir:$PATH" \
      AWS_CALL_LOG="$call_log" \
      STANDALONE_TASKS_JSON='{"web_cron":{"task_definition_arn":"'"$TD_PREFIX"':4","image_service_id":"worker"}}' \
      IMAGE_URIS_JSON="$IMAGE_URIS" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST" && echo "CALLS<<$(cat "'"$call_log"'")>>"'

    The status should be success
    The output should include "::warning::No image URI for service id 'worker' (standalone task web_cron); skipping"
    The output should include "CALLS<<>>"
  End

  It 'fails before registering when ECR reports ImageNotFoundException'
    When run env \
      PATH="$stub_dir:$PATH" \
      AWS_CALL_LOG="$call_log" \
      AWS_ECR_MODE="not-found" \
      STANDALONE_TASKS_JSON='{"web_cron":{"task_definition_arn":"'"$TD_PREFIX"':4","image_service_id":"web"}}' \
      IMAGE_URIS_JSON="$IMAGE_URIS" \
      bash -c 'cd "'"$workdir"'"; bash "$SCRIPT_UNDER_TEST"; status=$?; echo "CALLS<<$(cat "'"$call_log"'")>>"; exit "$status"'

    The status should equal 1
    The output should include "::error::ECR image not found for standalone task web_cron: web:abc123"
    The output should not include "register-task-definition"
  End

  It 'registers the task with its own service image, then deregisters only the older ACTIVE revisions'
    When run env \
      PATH="$stub_dir:$PATH" \
      AWS_CALL_LOG="$call_log" \
      STANDALONE_TASKS_JSON='{"web_cron":{"task_definition_arn":"'"$TD_PREFIX"':4","image_service_id":"web"}}' \
      IMAGE_URIS_JSON="$IMAGE_URIS" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST" && echo "REGISTERED=$(jq -c "[.containerDefinitions[0].image, .taskDefinitionArn, .revision, .status, .registeredAt]" td-web_cron.json)" && echo "OPS=$(cut -d" " -f1-2 "'"$call_log"'" | tr "\n" "|")" && echo "CALLS<<$(cat "'"$call_log"'")>>"'

    The status should be success
    The output should include "Registered standalone task web_cron -> ${TD_PREFIX}:5"
    The output should include "REGISTERED=[\"${WEB_IMAGE}\",null,null,null,null]"
    The output should include "OPS=ecr describe-images|ecs describe-task-definition|ecs register-task-definition|ecs list-task-definitions|ecs deregister-task-definition|ecs deregister-task-definition|"
    The output should include "ecs deregister-task-definition --task-definition ${TD_PREFIX}:3 "
    The output should include "ecs deregister-task-definition --task-definition ${TD_PREFIX}:4 "
    The output should not include "deregister-task-definition --task-definition ${TD_PREFIX}:5"
  End

  It 'fails a scheduled task without eventbridge_rule_name and deregisters nothing'
    When run env \
      PATH="$stub_dir:$PATH" \
      AWS_CALL_LOG="$call_log" \
      STANDALONE_TASKS_JSON='{"web_cron":{"task_definition_arn":"'"$TD_PREFIX"':4","image_service_id":"web","scheduled":true}}' \
      IMAGE_URIS_JSON="$IMAGE_URIS" \
      bash -c 'cd "'"$workdir"'"; bash "$SCRIPT_UNDER_TEST"; status=$?; echo "CALLS<<$(cat "'"$call_log"'")>>"; exit "$status"'

    The status should equal 1
    The output should include "::error::Standalone task web_cron requires an EventBridge target but is missing eventbridge_rule_name"
    The output should not include "deregister-task-definition"
  End

  It 'fails a scheduled task when the rule does not reference the new revision after put-targets, and deregisters nothing'
    When run env \
      PATH="$stub_dir:$PATH" \
      AWS_CALL_LOG="$call_log" \
      AWS_EB_VERIFIED_ARN="${TD_PREFIX}:4" \
      STANDALONE_TASKS_JSON='{"web_cron":{"task_definition_arn":"'"$TD_PREFIX"':4","image_service_id":"web","scheduled":true,"eventbridge_rule_name":"web-cron","eventbridge_bus_name":"jobs"}}' \
      IMAGE_URIS_JSON="$IMAGE_URIS" \
      bash -c 'cd "'"$workdir"'"; bash "$SCRIPT_UNDER_TEST"; status=$?; echo "CALLS<<$(cat "'"$call_log"'")>>"; exit "$status"'

    The status should equal 1
    The output should include "events put-targets --rule web-cron --event-bus-name jobs"
    The output should include "::error::EventBridge rule web-cron still points at ${TD_PREFIX}:4 after put-targets; expected ${TD_PREFIX}:5"
    The output should not include "deregister-task-definition"
  End

  It 'refuses to deregister an older revision the EventBridge rule still references after the rule was repointed'
    When run env \
      PATH="$stub_dir:$PATH" \
      AWS_CALL_LOG="$call_log" \
      AWS_EB_ARN_AFTER_VERIFY="${TD_PREFIX}:3" \
      STANDALONE_TASKS_JSON='{"web_cron":{"task_definition_arn":"'"$TD_PREFIX"':4","image_service_id":"web","scheduled":true,"eventbridge_rule_name":"web-cron","eventbridge_bus_name":"jobs"}}' \
      IMAGE_URIS_JSON="$IMAGE_URIS" \
      bash -c 'cd "'"$workdir"'"; bash "$SCRIPT_UNDER_TEST"; status=$?; echo "CALLS<<$(cat "'"$call_log"'")>>"; exit "$status"'

    The status should equal 1
    The output should include "Updated EventBridge rule web-cron -> ${TD_PREFIX}:5"
    The output should include "::error::Refusing to deregister ${TD_PREFIX}:3 because EventBridge rule web-cron still references it"
    The output should not include "deregister-task-definition"
  End
End
