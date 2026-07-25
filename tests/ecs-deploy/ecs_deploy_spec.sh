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
End
