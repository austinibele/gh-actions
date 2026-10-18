#!/usr/bin/env bash
# Registers a new task-definition revision for every standalone (cron/manual)
# ECS task on every run, updates direct EventBridge ECS targets when configured,
# then deregisters older ACTIVE revisions in the family.
#
# Re-registers unconditionally so direct EB targets can self-heal.
set -euo pipefail

: "${STANDALONE_TASKS_JSON:?STANDALONE_TASKS_JSON is required}"
: "${IMAGE_URIS_JSON:?IMAGE_URIS_JSON is required}"

validate_ecr_image_exists() {
  local image_uri="$1"
  local task_key="$2"

  if [[ -z "$image_uri" || "$image_uri" == "placeholder" || "$image_uri" == public.ecr.aws/* ]]; then
    return 0
  fi

  if [[ ! "$image_uri" =~ ^[0-9]+\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com/(.+):([^:]+)$ ]]; then
    echo "::warning::Cannot validate non-ECR image URI for standalone task $task_key: $image_uri"
    return 0
  fi

  local repo_name="${BASH_REMATCH[1]}"
  local image_tag="${BASH_REMATCH[2]}"

  local describe_err
  if describe_err="$(aws ecr describe-images --repository-name "$repo_name" --image-ids "imageTag=$image_tag" 2>&1 >/dev/null)"; then
    return 0
  fi

  if [[ "$describe_err" == *ImageNotFoundException* || "$describe_err" == *RepositoryNotFoundException* ]]; then
    echo "::error::ECR image not found for standalone task $task_key: $repo_name:$image_tag"
    return 1
  fi

  echo "::warning::Could not verify ECR image for standalone task $task_key ($repo_name:$image_tag); skipping existence check: $describe_err"
  return 0
}

update_task() {
  local task_key="$1"
  local task_meta="$2"

  local task_definition_arn image_service_id image_uri
  task_definition_arn="$(echo "$task_meta" | jq -r '.task_definition_arn // empty')"
  image_service_id="$(echo "$task_meta" | jq -r '.image_service_id // empty')"

  if [[ -z "$task_definition_arn" || -z "$image_service_id" ]]; then
    echo "::warning::Standalone task $task_key is missing task_definition_arn or image_service_id; skipping"
    return 0
  fi

  image_uri="$(echo "$IMAGE_URIS_JSON" | jq -r --arg id "$image_service_id" '.[$id] // empty')"
  if [[ -z "$image_uri" ]]; then
    echo "::warning::No image URI for service id '$image_service_id' (standalone task $task_key); skipping"
    return 0
  fi

  validate_ecr_image_exists "$image_uri" "$task_key"

  aws ecs describe-task-definition --task-definition "$task_definition_arn" --query taskDefinition --output json > "td-${task_key}-base.json"

  local family
  family="$(jq -r '.family' "td-${task_key}-base.json")"

  jq -c --arg image "$image_uri" '
    .containerDefinitions[0].image = $image
    | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy, .deregisteredAt)
  ' "td-${task_key}-base.json" > "td-${task_key}.json"

  local new_arn
  new_arn="$(aws ecs register-task-definition --cli-input-json "file://td-${task_key}.json" --query taskDefinition.taskDefinitionArn --output text)"
  echo "Registered standalone task $task_key -> $new_arn"

  # Update EventBridge targets BEFORE deregistering old revisions so the rule
  # never points at an inactive task definition.
  local scheduled eventbridge_target rule_name eventbridge_bus_name
  scheduled="$(echo "$task_meta" | jq -r '.scheduled // false')"
  eventbridge_target="$(echo "$task_meta" | jq -r '.eventbridge_target // false')"
  rule_name="$(echo "$task_meta" | jq -r '.eventbridge_rule_name // empty')"
  eventbridge_bus_name="$(echo "$task_meta" | jq -r '.eventbridge_bus_name // empty')"

  if [[ "$scheduled" == "true" || "$eventbridge_target" == "true" ]] && [[ -z "$rule_name" ]]; then
    echo "::error::Standalone task $task_key requires an EventBridge target but is missing eventbridge_rule_name"
    return 1
  fi

  if [[ "$scheduled" == "true" || "$eventbridge_target" == "true" ]]; then
    local -a eventbridge_bus_args=()
    if [[ -n "$eventbridge_bus_name" && "$eventbridge_bus_name" != "default" ]]; then
      eventbridge_bus_args=(--event-bus-name "$eventbridge_bus_name")
    fi

    local target_json
    target_json="$(aws events list-targets-by-rule --rule "$rule_name" "${eventbridge_bus_args[@]}" --query 'Targets[0]' --output json)"
    if [[ -z "$target_json" || "$target_json" == "null" ]]; then
      echo "::error::EventBridge rule $rule_name has no existing target to update for $task_key"
      return 1
    fi

    local updated_target put_response failed_count
    updated_target="$(echo "$target_json" | jq -c --arg arn "$new_arn" '.EcsParameters.TaskDefinitionArn = $arn | [.]')"
    put_response="$(aws events put-targets --rule "$rule_name" "${eventbridge_bus_args[@]}" --targets "$updated_target")"
    failed_count="$(echo "$put_response" | jq -r '.FailedEntryCount // 0')"
    if [[ "$failed_count" != "0" ]]; then
      # Don't deregister old revisions when the EB update didn't actually take —
      # leave the previous ACTIVE revision in place as a recovery option.
      echo "::error::put-targets reported $failed_count failed entries for rule $rule_name; response: $put_response"
      return 1
    fi

    local verified_arn verified_status
    verified_arn="$(aws events list-targets-by-rule --rule "$rule_name" "${eventbridge_bus_args[@]}" --query 'Targets[0].EcsParameters.TaskDefinitionArn' --output text)"
    if [[ "$verified_arn" != "$new_arn" ]]; then
      echo "::error::EventBridge rule $rule_name still points at $verified_arn after put-targets; expected $new_arn"
      return 1
    fi

    verified_status="$(aws ecs describe-task-definition --task-definition "$verified_arn" --query taskDefinition.status --output text)"
    if [[ "$verified_status" != "ACTIVE" ]]; then
      echo "::error::EventBridge rule $rule_name points at $verified_arn with status $verified_status; expected ACTIVE"
      return 1
    fi

    echo "Updated EventBridge rule $rule_name -> $new_arn"
  fi

  # Deregister all older ACTIVE revisions in this family
  while IFS= read -r old_arn; do
    [[ -z "$old_arn" || "$old_arn" == "$new_arn" ]] && continue
    if [[ "$scheduled" == "true" || "$eventbridge_target" == "true" ]]; then
      local current_target_arn
      current_target_arn="$(aws events list-targets-by-rule --rule "$rule_name" "${eventbridge_bus_args[@]}" --query 'Targets[0].EcsParameters.TaskDefinitionArn' --output text)"
      if [[ "$current_target_arn" == "$old_arn" ]]; then
        echo "::error::Refusing to deregister $old_arn because EventBridge rule $rule_name still references it"
        return 1
      fi
    fi
    aws ecs deregister-task-definition --task-definition "$old_arn" --output text > /dev/null
    echo "Deregistered old revision $old_arn"
  done < <(aws ecs list-task-definitions --family-prefix "$family" --status ACTIVE --query 'taskDefinitionArns[]' --output text | tr '\t' '\n')
}

while IFS= read -r entry; do
  [[ -z "$entry" ]] && continue
  task_key="$(echo "$entry" | jq -r '.key')"
  task_meta="$(echo "$entry" | jq -c '.value')"
  update_task "$task_key" "$task_meta"
done < <(echo "$STANDALONE_TASKS_JSON" | jq -c 'to_entries[]')
