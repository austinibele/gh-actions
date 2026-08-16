#shellspec
# Tests for .github/ecs-deploy/ecs-deploy.sh metadata classification.
# Stubs terraform/aws and stops before real AWS mutations.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_UNDER_TEST="${SCRIPT_DIR}/../../.github/ecs-deploy/ecs-deploy.sh"

_make_terraform_stub() {
  local stub_dir="$1"
  local mode="$2"
  cat >"${stub_dir}/terraform" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$1" == "output" && "\$2" == "-json" ]]; then
  case "${mode}" in
    ok-empty)
      printf '%s\n' '{}'
      exit 0
      ;;
    ok-populated)
      cat <<'JSON'
{
  "crm_ecs_deploy_metadata": {
    "value": {
      "cluster_name": "crm-dev",
      "services": {
        "backend": {
          "service_name": "crm-backend",
          "task_definition_arn": "arn:aws:ecs:us-east-1:123:task-definition/crm-backend:1",
          "container_names": {"backend": "backend"}
        }
      }
    }
  }
}
JSON
      exit 0
      ;;
    ok-null-meta)
      cat <<'JSON'
{
  "crm_ecs_deploy_metadata": {"value": null},
  "other_output": {"value": "x"}
}
JSON
      exit 0
      ;;
    ok-missing-meta)
      cat <<'JSON'
{
  "other_output": {"value": "x"}
}
JSON
      exit 0
      ;;
    ok-incomplete-cluster)
      cat <<'JSON'
{
  "crm_ecs_deploy_metadata": {
    "value": {
      "services": {}
    }
  }
}
JSON
      exit 0
      ;;
    fail-output)
      echo "Error: Backend initialization required" >&2
      exit 1
      ;;
    malformed)
      printf '%s\n' 'not-json'
      exit 0
      ;;
  esac
fi
echo "unexpected terraform args: \$*" >&2
exit 1
EOF
  chmod +x "${stub_dir}/terraform"
}

_make_waiter_aws_stub() {
  local stub_dir="$1"

  cat >"${stub_dir}/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1 $2" in
  "ecs describe-task-definition")
    cat <<'JSON'
{"family":"crm-backend","containerDefinitions":[{"name":"backend","image":"old-uri"}]}
JSON
    ;;
  "ecs register-task-definition")
    printf '%s\n' 'arn:aws:ecs:us-east-1:123:task-definition/crm-backend:2'
    ;;
  "ecs update-service")
    printf '%s\n' '{}'
    ;;
  "ecs describe-services")
    poll_count="$(cat "$AWS_POLL_STATE")"
    poll_count="$((poll_count + 1))"
    printf '%s\n' "$poll_count" >"$AWS_POLL_STATE"
    if [[ "$AWS_POLL_MODE" == "recover" && "$poll_count" -ge 2 ]]; then
      printf '%s\n' '{"failures":[],"services":[{"desiredCount":1,"runningCount":1,"pendingCount":0,"deployments":[{"status":"PRIMARY"}],"events":[]}]}'
    else
      printf '%s\n' '{"failures":[],"services":[{"desiredCount":1,"runningCount":0,"pendingCount":1,"deployments":[{"status":"PRIMARY"},{"status":"ACTIVE"}],"events":[{"message":"service-events"}]}]}'
    fi
    ;;
esac
EOF
  chmod +x "${stub_dir}/aws"
}

_make_waiter_time_stubs() {
  local stub_dir="$1"

  cat >"${stub_dir}/date" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
time_count="$(cat "$AWS_TIME_STATE")"
time_count="$((time_count + 1))"
printf '%s\n' "$time_count" >"$AWS_TIME_STATE"
if [[ "$AWS_TIME_MODE" == "expire" && "$time_count" -ge 2 ]]; then
  printf '%s\n' '2201'
else
  printf '%s\n' "$((999 + time_count))"
fi
EOF
  chmod +x "${stub_dir}/date"

  cat >"${stub_dir}/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${stub_dir}/sleep"
}

Describe 'ecs-deploy.sh metadata classification'
  It 'skips with notice when terraform output is empty object {}'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    workdir=$(mktemp -d)
    gh_out=$(mktemp)
    _make_terraform_stub "$stub_dir" "ok-empty"

    When run env \
      PATH="$stub_dir:$PATH" \
      TERRAFORM_INIT_COMMAND="true" \
      DEPLOY_METADATA_OUTPUT="crm_ecs_deploy_metadata" \
      IMAGE_URIS_JSON='{"backend":"uri"}' \
      REBUILT_SERVICE_IDS_JSON='["backend"]' \
      ENV_OR_INFRA_CHANGED="true" \
      SERVICE_GROUPS_JSON='{"backend":{"service_ids":["backend"]}}' \
      GITHUB_OUTPUT="$gh_out" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST" && echo "OUT<<$(cat "'"$gh_out"'")>>" && test -f tf-output.json && echo TF_OUTPUT_EXISTS=1'

    The status should be success
    The output should include "::notice::"
    The output should include "has not been applied"
    The output should include "metadata_configured=false"
    The output should include "deploy_skipped=true"
    The output should include "TF_OUTPUT_EXISTS=1"
  End

  It 'fails when terraform output exits non-zero'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    workdir=$(mktemp -d)
    gh_out=$(mktemp)
    _make_terraform_stub "$stub_dir" "fail-output"

    When run env \
      PATH="$stub_dir:$PATH" \
      TERRAFORM_INIT_COMMAND="true" \
      DEPLOY_METADATA_OUTPUT="crm_ecs_deploy_metadata" \
      IMAGE_URIS_JSON='{}' \
      REBUILT_SERVICE_IDS_JSON='[]' \
      ENV_OR_INFRA_CHANGED="false" \
      SERVICE_GROUPS_JSON='{}' \
      GITHUB_OUTPUT="$gh_out" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST"'

    The status should be failure
    The stderr should include "Backend initialization required"
  End

  It 'fails when terraform init command exits non-zero'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    workdir=$(mktemp -d)
    gh_out=$(mktemp)
    _make_terraform_stub "$stub_dir" "ok-empty"

    When run env \
      PATH="$stub_dir:$PATH" \
      TERRAFORM_INIT_COMMAND="exit 1" \
      DEPLOY_METADATA_OUTPUT="crm_ecs_deploy_metadata" \
      IMAGE_URIS_JSON='{}' \
      REBUILT_SERVICE_IDS_JSON='[]' \
      ENV_OR_INFRA_CHANGED="false" \
      SERVICE_GROUPS_JSON='{}' \
      GITHUB_OUTPUT="$gh_out" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST"'

    The status should be failure
  End

  It 'fails with error when tf-output.json is malformed'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    workdir=$(mktemp -d)
    gh_out=$(mktemp)
    _make_terraform_stub "$stub_dir" "malformed"

    When run env \
      PATH="$stub_dir:$PATH" \
      TERRAFORM_INIT_COMMAND="true" \
      DEPLOY_METADATA_OUTPUT="crm_ecs_deploy_metadata" \
      IMAGE_URIS_JSON='{}' \
      REBUILT_SERVICE_IDS_JSON='[]' \
      ENV_OR_INFRA_CHANGED="false" \
      SERVICE_GROUPS_JSON='{}' \
      GITHUB_OUTPUT="$gh_out" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST"'

    The status should be failure
    The output should include "::error::"
    The output should include "Malformed Terraform output"
  End

  It 'fails when state has outputs but deploy-metadata is absent'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    workdir=$(mktemp -d)
    gh_out=$(mktemp)
    _make_terraform_stub "$stub_dir" "ok-missing-meta"

    When run env \
      PATH="$stub_dir:$PATH" \
      TERRAFORM_INIT_COMMAND="true" \
      DEPLOY_METADATA_OUTPUT="crm_ecs_deploy_metadata" \
      IMAGE_URIS_JSON='{}' \
      REBUILT_SERVICE_IDS_JSON='[]' \
      ENV_OR_INFRA_CHANGED="false" \
      SERVICE_GROUPS_JSON='{}' \
      GITHUB_OUTPUT="$gh_out" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST"'

    The status should be failure
    The output should include "::error::"
    The output should include "absent or null"
  End

  It 'fails when state has outputs but deploy-metadata value is null'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    workdir=$(mktemp -d)
    gh_out=$(mktemp)
    _make_terraform_stub "$stub_dir" "ok-null-meta"

    When run env \
      PATH="$stub_dir:$PATH" \
      TERRAFORM_INIT_COMMAND="true" \
      DEPLOY_METADATA_OUTPUT="crm_ecs_deploy_metadata" \
      IMAGE_URIS_JSON='{}' \
      REBUILT_SERVICE_IDS_JSON='[]' \
      ENV_OR_INFRA_CHANGED="false" \
      SERVICE_GROUPS_JSON='{}' \
      GITHUB_OUTPUT="$gh_out" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST"'

    The status should be failure
    The output should include "::error::"
    The output should include "absent or null"
  End

  It 'skips when deploy-metadata is absent and the workflow explicitly allows it'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    workdir=$(mktemp -d)
    gh_out=$(mktemp)
    _make_terraform_stub "$stub_dir" "ok-missing-meta"

    When run env \
      PATH="$stub_dir:$PATH" \
      TERRAFORM_INIT_COMMAND="true" \
      DEPLOY_METADATA_OUTPUT="crm_ecs_deploy_metadata" \
      IMAGE_URIS_JSON='{}' \
      REBUILT_SERVICE_IDS_JSON='[]' \
      ENV_OR_INFRA_CHANGED="false" \
      SERVICE_GROUPS_JSON='{}' \
      SKIP_WHEN_METADATA_ABSENT="true" \
      GITHUB_OUTPUT="$gh_out" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST" && echo "OUT<<$(cat "'"$gh_out"'")>>"'

    The status should be success
    The output should include "Skipping deployment as configured"
    The output should include "metadata_configured=false"
    The output should include "deploy_skipped=true"
  End

  It 'skips when deploy-metadata is null and the workflow explicitly allows it'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    workdir=$(mktemp -d)
    gh_out=$(mktemp)
    _make_terraform_stub "$stub_dir" "ok-null-meta"

    When run env \
      PATH="$stub_dir:$PATH" \
      TERRAFORM_INIT_COMMAND="true" \
      DEPLOY_METADATA_OUTPUT="crm_ecs_deploy_metadata" \
      IMAGE_URIS_JSON='{}' \
      REBUILT_SERVICE_IDS_JSON='[]' \
      ENV_OR_INFRA_CHANGED="false" \
      SERVICE_GROUPS_JSON='{}' \
      SKIP_WHEN_METADATA_ABSENT="true" \
      GITHUB_OUTPUT="$gh_out" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST" && echo "OUT<<$(cat "'"$gh_out"'")>>"'

    The status should be success
    The output should include "Skipping deployment as configured"
    The output should include "metadata_configured=false"
    The output should include "deploy_skipped=true"
  End

  It 'fails when metadata is present but cluster_name is missing'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    workdir=$(mktemp -d)
    gh_out=$(mktemp)
    _make_terraform_stub "$stub_dir" "ok-incomplete-cluster"

    When run env \
      PATH="$stub_dir:$PATH" \
      TERRAFORM_INIT_COMMAND="true" \
      DEPLOY_METADATA_OUTPUT="crm_ecs_deploy_metadata" \
      IMAGE_URIS_JSON='{}' \
      REBUILT_SERVICE_IDS_JSON='[]' \
      ENV_OR_INFRA_CHANGED="false" \
      SERVICE_GROUPS_JSON='{}' \
      GITHUB_OUTPUT="$gh_out" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST"'

    The status should be failure
    The output should include "::error::"
    The output should include "missing cluster_name"
  End

  It 'writes metadata_configured=true before AWS calls when metadata is complete'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    workdir=$(mktemp -d)
    gh_out=$(mktemp)
    _make_terraform_stub "$stub_dir" "ok-populated"
    cat >"${stub_dir}/aws" <<'EOF'
#!/usr/bin/env bash
echo "AWS_CALLED $*" >&2
exit 42
EOF
    chmod +x "${stub_dir}/aws"

    When run env \
      PATH="$stub_dir:$PATH" \
      TERRAFORM_INIT_COMMAND="true" \
      DEPLOY_METADATA_OUTPUT="crm_ecs_deploy_metadata" \
      IMAGE_URIS_JSON='{"backend":"uri"}' \
      REBUILT_SERVICE_IDS_JSON='["backend"]' \
      ENV_OR_INFRA_CHANGED="true" \
      SERVICE_GROUPS_JSON='{"backend":{"service_ids":["backend"]}}' \
      GITHUB_OUTPUT="$gh_out" \
      bash -c 'cd "'"$workdir"'" && set +e; bash "$SCRIPT_UNDER_TEST"; echo "OUT<<$(cat "'"$gh_out"'")>>"; echo AWS_SEEN=1'

    The status should be success
    The output should include "metadata_configured=true"
    The output should include "deploy_skipped=false"
    The stderr should include "AWS_CALLED"
  End

  It 'tags newly registered task definitions with the configured Repository value'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    workdir=$(mktemp -d)
    gh_out=$(mktemp)
    _make_terraform_stub "$stub_dir" "ok-populated"
    cat >"${stub_dir}/aws" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "AWS_CALLED $*" >&2
case "$1 $2" in
  "ecs describe-task-definition")
    cat <<'JSON'
{"family":"crm-backend","containerDefinitions":[{"name":"backend","image":"old-uri"}]}
JSON
    ;;
  "ecs register-task-definition")
    printf '%s\n' 'arn:aws:ecs:us-east-1:123:task-definition/crm-backend:2'
    ;;
  "ecs describe-services")
    printf '%s\n' '{"failures":[],"services":[{"desiredCount":1,"runningCount":1,"deployments":[{"status":"PRIMARY"}]}]}'
    ;;
esac
EOF
    chmod +x "${stub_dir}/aws"

    When run env \
      PATH="$stub_dir:$PATH" \
      TERRAFORM_INIT_COMMAND="true" \
      DEPLOY_METADATA_OUTPUT="crm_ecs_deploy_metadata" \
      IMAGE_URIS_JSON='{"backend":"new-uri"}' \
      REBUILT_SERVICE_IDS_JSON='["backend"]' \
      ENV_OR_INFRA_CHANGED="true" \
      SERVICE_GROUPS_JSON='{"backend":{"service_ids":["backend"]}}' \
      REPOSITORY_TAG="vectorfabric-ui" \
      GITHUB_OUTPUT="$gh_out" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST"'

    The status should be success
    The output should include "Deploying backend"
    The output should include "Waiting up to 20 minute(s)"
    The stderr should include "AWS_CALLED ecs register-task-definition"
    The stderr should include "--tags key=Repository,value=vectorfabric-ui"
  End

  It 'skips a requested service group absent from metadata.services and continues (no hard fail)'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    workdir=$(mktemp -d)
    gh_out=$(mktemp)
    _make_terraform_stub "$stub_dir" "ok-populated"
    cat >"${stub_dir}/aws" <<'EOF'
#!/usr/bin/env bash
echo "AWS_SHOULD_NOT_RUN $*" >&2
exit 42
EOF
    chmod +x "${stub_dir}/aws"

    When run env \
      PATH="$stub_dir:$PATH" \
      TERRAFORM_INIT_COMMAND="true" \
      DEPLOY_METADATA_OUTPUT="crm_ecs_deploy_metadata" \
      IMAGE_URIS_JSON='{"messenger":"uri"}' \
      REBUILT_SERVICE_IDS_JSON='["messenger"]' \
      ENV_OR_INFRA_CHANGED="true" \
      SERVICE_GROUPS_JSON='{"messenger":{"service_ids":["messenger"]}}' \
      GITHUB_OUTPUT="$gh_out" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST"; echo "OUT<<$(cat "'"$gh_out"'")>>"'

    The status should be success
    The output should include "Skipping messenger"
    The output should include "metadata_configured=true"
    The output should include "deploy_skipped=false"
    The stderr should not include "AWS_SHOULD_NOT_RUN"
  End

  It 'keeps polling until the ECS service stabilizes within the configured minute timeout'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    workdir=$(mktemp -d)
    gh_out=$(mktemp)
    poll_state=$(mktemp)
    time_state=$(mktemp)
    printf '%s\n' '0' >"$poll_state"
    printf '%s\n' '0' >"$time_state"
    _make_terraform_stub "$stub_dir" "ok-populated"
    _make_waiter_aws_stub "$stub_dir"
    _make_waiter_time_stubs "$stub_dir"

    When run env \
      PATH="$stub_dir:$PATH" \
      TERRAFORM_INIT_COMMAND="true" \
      DEPLOY_METADATA_OUTPUT="crm_ecs_deploy_metadata" \
      IMAGE_URIS_JSON='{"backend":"new-uri"}' \
      REBUILT_SERVICE_IDS_JSON='["backend"]' \
      ENV_OR_INFRA_CHANGED="true" \
      SERVICE_GROUPS_JSON='{"backend":{"service_ids":["backend"]}}' \
      SERVICES_STABLE_TIMEOUT_MINUTES="20" \
      AWS_POLL_MODE="recover" \
      AWS_POLL_STATE="$poll_state" \
      AWS_TIME_MODE="advance" \
      AWS_TIME_STATE="$time_state" \
      GITHUB_OUTPUT="$gh_out" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST"'

    The status should be success
    The output should include "Waiting up to 20 minute(s)"
    The output should include "polling every 15 seconds"
    The output should include "is stable"
  End

  It 'prints ECS service diagnostics when the minute timeout expires'
    stub_dir=$(mktemp -d)
    PATH="$stub_dir:$PATH"
    workdir=$(mktemp -d)
    gh_out=$(mktemp)
    poll_state=$(mktemp)
    time_state=$(mktemp)
    printf '%s\n' '0' >"$poll_state"
    printf '%s\n' '0' >"$time_state"
    _make_terraform_stub "$stub_dir" "ok-populated"
    _make_waiter_aws_stub "$stub_dir"
    _make_waiter_time_stubs "$stub_dir"

    When run env \
      PATH="$stub_dir:$PATH" \
      TERRAFORM_INIT_COMMAND="true" \
      DEPLOY_METADATA_OUTPUT="crm_ecs_deploy_metadata" \
      IMAGE_URIS_JSON='{"backend":"new-uri"}' \
      REBUILT_SERVICE_IDS_JSON='["backend"]' \
      ENV_OR_INFRA_CHANGED="true" \
      SERVICE_GROUPS_JSON='{"backend":{"service_ids":["backend"]}}' \
      SERVICES_STABLE_TIMEOUT_MINUTES="20" \
      AWS_POLL_MODE="fail" \
      AWS_POLL_STATE="$poll_state" \
      AWS_TIME_MODE="expire" \
      AWS_TIME_STATE="$time_state" \
      GITHUB_OUTPUT="$gh_out" \
      bash -c 'cd "'"$workdir"'" && bash "$SCRIPT_UNDER_TEST"'

    The status should be failure
    The output should include "did not stabilize within 20 minute(s)"
    The output should include "ECS service stability diagnostics"
    The output should include "service-events"
  End
End
