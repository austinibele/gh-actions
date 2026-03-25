#!/usr/bin/env bash
set -euo pipefail

: "${TERRAFORM_INIT_COMMAND:?TERRAFORM_INIT_COMMAND is required}"
: "${DEPLOY_METADATA_OUTPUT:?DEPLOY_METADATA_OUTPUT is required}"
: "${IMAGE_URIS_JSON:?IMAGE_URIS_JSON is required}"
: "${REBUILT_SERVICE_IDS_JSON:?REBUILT_SERVICE_IDS_JSON is required}"
: "${ENV_OR_INFRA_CHANGED:?ENV_OR_INFRA_CHANGED is required}"
: "${SERVICE_GROUPS_JSON:?SERVICE_GROUPS_JSON is required}"

bash -c "$TERRAFORM_INIT_COMMAND"
terraform output -json > tf-output.json || printf '{}' > tf-output.json
deploy_metadata="$(jq -c --arg output "$DEPLOY_METADATA_OUTPUT" '.[$output].value // empty' tf-output.json)"
if [[ -z "$deploy_metadata" || "$deploy_metadata" == "null" ]]; then
  echo "Terraform output '$DEPLOY_METADATA_OUTPUT' is null or absent — no ECS services configured for this environment. Skipping deployment."
  exit 0
fi
cluster_name="$(echo "$deploy_metadata" | jq -r '.cluster_name // empty')"
if [[ -z "$cluster_name" ]]; then
  echo "::error::Deploy metadata is missing cluster_name"
  exit 1
fi
service_groups_json="$SERVICE_GROUPS_JSON"

deploy_service_group() {
  local service_key="$1"
  local service_ids_json="$2"
  local service_metadata service_name task_definition_arn group_has_rebuilt="false"

  service_metadata="$(echo "$deploy_metadata" | jq -c --arg key "$service_key" '.services[$key] // empty')"
  if [[ -z "$service_metadata" ]]; then
    echo "Skipping $service_key; no deploy metadata found"
    return 0
  fi

  while IFS= read -r service_id; do
    [[ -z "$service_id" ]] && continue
    if echo "$REBUILT_SERVICE_IDS_JSON" | jq -e --arg id "$service_id" 'index($id) != null' >/dev/null; then
      group_has_rebuilt="true"
      break
    fi
  done < <(echo "$service_ids_json" | jq -r '.[]')

  if [[ "$ENV_OR_INFRA_CHANGED" != "true" && "$group_has_rebuilt" != "true" ]]; then
    echo "Skipping $service_key; no rebuilt images and no env/infra change"
    return 0
  fi

  service_name="$(echo "$service_metadata" | jq -r '.service_name // empty')"
  task_definition_arn="$(echo "$service_metadata" | jq -r '.task_definition_arn // empty')"
  if [[ -z "$service_name" || -z "$task_definition_arn" ]]; then
    echo "::error::Deploy metadata for $service_key is incomplete"
    exit 1
  fi

  aws ecs describe-task-definition --task-definition "$task_definition_arn" --query taskDefinition --output json > "task-definition-${service_key}-base.json"
  container_image_map='{}'

  while IFS= read -r service_id; do
    [[ -z "$service_id" ]] && continue
    container_name="$(echo "$service_metadata" | jq -r --arg id "$service_id" '.container_names[$id] // empty')"
    image_uri="$(echo "$IMAGE_URIS_JSON" | jq -r --arg id "$service_id" '.[$id] // empty')"

    if [[ -z "$container_name" ]]; then
      echo "::error::Missing container mapping for $service_id in service group $service_key"
      exit 1
    fi
    if [[ -z "$image_uri" ]]; then
      echo "::error::Missing image URI for $service_id in service group $service_key"
      exit 1
    fi

    container_image_map="$(echo "$container_image_map" | jq -c --arg name "$container_name" --arg image "$image_uri" '. + {($name): $image}')"
  done < <(echo "$service_ids_json" | jq -r '.[]')

  jq -c --argjson image_map "$container_image_map" '
    .containerDefinitions |= map(
      if (($image_map[.name] // "") != "") then .image = $image_map[.name] else . end
    )
    | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)
  ' "task-definition-${service_key}-base.json" > "task-definition-${service_key}.json"

  new_task_definition_arn="$(aws ecs register-task-definition --cli-input-json "file://task-definition-${service_key}.json" --query taskDefinition.taskDefinitionArn --output text)"
  echo "Deploying $service_key via $service_name -> $new_task_definition_arn"
  aws ecs update-service --cluster "$cluster_name" --service "$service_name" --task-definition "$new_task_definition_arn"
  aws ecs wait services-stable --cluster "$cluster_name" --services "$service_name"
}

while IFS= read -r service_group; do
  [[ -z "$service_group" ]] && continue
  service_key="$(echo "$service_group" | jq -r '.key')"
  service_ids_json="$(echo "$service_group" | jq -c '.value.service_ids // []')"
  deploy_service_group "$service_key" "$service_ids_json"
done < <(echo "$service_groups_json" | jq -c 'to_entries[]')
