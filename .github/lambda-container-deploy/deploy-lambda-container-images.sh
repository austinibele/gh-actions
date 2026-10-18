#!/usr/bin/env bash
set -euo pipefail

: "${DEPLOY_METADATA_OUTPUT:=crm_ecs_deploy_metadata}"
: "${IMAGE_URIS_JSON:?IMAGE_URIS_JSON is required}"
: "${REBUILT_SERVICE_IDS_JSON:?REBUILT_SERVICE_IDS_JSON is required}"
: "${ENV_OR_INFRA_CHANGED:?ENV_OR_INFRA_CHANGED is required}"
if [[ -z "${EXPECTED_LAMBDA_FUNCTIONS_JSON:-}" ]]; then
  EXPECTED_LAMBDA_FUNCTIONS_JSON='{}'
fi
: "${LAMBDA_UPDATE_POLL_SECONDS:=5}"
: "${LAMBDA_UPDATE_MAX_POLLS:=60}"

# update-function-code returns while the update is still in progress. The job must fail
# when the function does not end up on the new image, because the deployment ledger
# records success after this script.
wait_for_lambda_update() {
  local fn_name="$1" result status="" reason=""
  for ((poll = 1; poll <= LAMBDA_UPDATE_MAX_POLLS; poll++)); do
    if ! result="$(aws lambda get-function --function-name "$fn_name" \
      --query '[Configuration.LastUpdateStatus, Configuration.LastUpdateStatusReason]' --output text)"; then
      echo "::error::Could not read the update status of Lambda $fn_name"
      return 1
    fi
    IFS=$'\t' read -r status reason <<<"$result"
    case "$status" in
      Successful)
        echo "Lambda $fn_name update finished: Successful"
        return 0
        ;;
      Failed)
        echo "::error::Lambda $fn_name update failed: $reason"
        return 1
        ;;
    esac
    sleep "$LAMBDA_UPDATE_POLL_SECONDS"
  done
  echo "::error::Lambda $fn_name update did not finish after $LAMBDA_UPDATE_MAX_POLLS checks (last status: '${status:-unknown}')"
  return 1
}

if ! expected_lambdas="$(jq -ce . <<<"$EXPECTED_LAMBDA_FUNCTIONS_JSON")"; then
  echo "::error::EXPECTED_LAMBDA_FUNCTIONS_JSON is not valid JSON"
  exit 1
fi

if [[ ! -f tf-output.json ]]; then
  echo "::error::tf-output.json not found in $(pwd) — run ecs-deploy (terraform output) first"
  exit 1
fi

deploy_metadata="$(jq -c --arg o "$DEPLOY_METADATA_OUTPUT" '.[$o].value // empty' tf-output.json)"
if [[ -z "$deploy_metadata" || "$deploy_metadata" == "null" ]]; then
  if [[ "$(echo "$expected_lambdas" | jq 'length')" -gt 0 ]]; then
    echo "::error::Deploy metadata is empty but Lambda targets are expected"
    exit 1
  fi
  echo "Deploy metadata is empty; skipping lambda image updates"
  exit 0
fi

lambdas="$(echo "$deploy_metadata" | jq -c '.lambda_functions // {}')"
legacy_lambda="$(echo "$deploy_metadata" | jq -c '.lambda // {}')"

if [[ "$lambdas" == "{}" && "$(echo "$legacy_lambda" | jq -r '.function_name // empty')" != "" ]]; then
  if [[ "$(echo "$expected_lambdas" | jq 'length')" -ne 1 ]]; then
    echo "::error::Legacy lambda deploy metadata requires exactly one expected Lambda mapping"
    exit 1
  fi
  lambdas="$(
    jq -cn \
      --argjson legacy "$legacy_lambda" \
      --argjson expected "$expected_lambdas" \
      '($expected | to_entries[0]) as $entry
       | {($entry.key): {
           function_name: $legacy.function_name,
           image_service_id: $entry.value.image_service_id
         }}'
  )"
  echo "Using legacy lambda deploy metadata with the configured Lambda mapping"
fi

while IFS= read -r expected_row; do
  expected_key="$(echo "$expected_row" | jq -r '.key')"
  expected_image_sid="$(echo "$expected_row" | jq -r '.value.image_service_id // empty')"
  actual_image_sid="$(echo "$lambdas" | jq -r --arg key "$expected_key" '.[$key].image_service_id // empty')"
  if [[ -z "$expected_image_sid" ]]; then
    echo "::error::Expected Lambda '$expected_key' is missing image_service_id"
    exit 1
  fi
  if [[ -z "$actual_image_sid" ]]; then
    echo "::error::Expected Lambda '$expected_key' is missing from deploy metadata"
    exit 1
  fi
  if [[ "$actual_image_sid" != "$expected_image_sid" ]]; then
    echo "::error::Lambda '$expected_key' image_service_id mismatch: expected '$expected_image_sid', got '$actual_image_sid'"
    exit 1
  fi
done < <(echo "$expected_lambdas" | jq -c 'to_entries[]')

if [[ -z "$lambdas" || "$lambdas" == "null" || "$lambdas" == "{}" ]]; then
  echo "No lambda_functions in deploy metadata; skipping"
  exit 0
fi

while IFS= read -r row; do
  fn_name="$(echo "$row" | jq -r '.value.function_name // empty')"
  image_sid="$(echo "$row" | jq -r '.value.image_service_id // empty')"
  if [[ -z "$fn_name" || -z "$image_sid" ]]; then
    echo "::error::Malformed lambda entry in deploy metadata (missing function_name or image_service_id): $row"
    exit 1
  fi

  should_update="false"
  if echo "$REBUILT_SERVICE_IDS_JSON" | jq -e --arg id "$image_sid" 'index($id) != null' >/dev/null; then
    should_update="true"
  elif [[ "$ENV_OR_INFRA_CHANGED" == "true" ]]; then
    # The deploy metadata lists every Lambda in the stack, including ones whose image
    # another pipeline builds and rolls (CRM Primary owns media-processor, CRM AI owns
    # ads-clustering). An env/infra change only redeploys the Lambdas this workflow
    # owns: those it expects or has an image URI for.
    if echo "$expected_lambdas" | jq -e --arg id "$image_sid" '[.[].image_service_id] | index($id) != null' >/dev/null ||
      echo "$IMAGE_URIS_JSON" | jq -e --arg id "$image_sid" 'has($id)' >/dev/null; then
      should_update="true"
    else
      echo "Skip $fn_name (image service $image_sid is built and deployed by another pipeline)"
      continue
    fi
  fi
  if [[ "$should_update" != "true" ]]; then
    echo "Skip $fn_name (image service $image_sid not rebuilt, env/infra unchanged)"
    continue
  fi

  uri="$(echo "$IMAGE_URIS_JSON" | jq -r --arg id "$image_sid" '.[$id] // empty')"
  if [[ -z "${uri//[[:space:]]/}" ]]; then
    echo "::error::Missing image URI for service id '$image_sid' (lambda $fn_name)"
    exit 1
  fi

  echo "Updating lambda $fn_name with image $uri"
  aws lambda update-function-code --function-name "$fn_name" --image-uri "$uri" >/dev/null
  wait_for_lambda_update "$fn_name"
done < <(echo "$lambdas" | jq -c 'to_entries[]')
