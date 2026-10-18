# ECS Update Standalone Tasks Action

Registers a new task-definition revision with the current container image for every standalone (cron or manual) ECS task in the Terraform deploy metadata, on every run, so a direct EventBridge target can self-heal. Before registering, an ECR image URI is checked with `ecr describe-images`: a missing image or repository fails the step, any other lookup error is a warning. A task with `scheduled` or `eventbridge_target` gets its EventBridge rule target repointed at the new revision and verified (the rule must reference the new ARN, which must be ACTIVE) before older ACTIVE revisions in the family are deregistered; a revision the rule still references is never deregistered. A task missing `task_definition_arn`, `image_service_id` or an image URI is skipped with a warning. Call it after `ecs-deploy`, in the same job and with the same AWS credentials, when `ecs-deploy` reports `metadata_configured == 'true'`.

## Usage

```yaml
- uses: austinibele/gh-actions/.github/ecs-deploy@main
  id: ecs-deploy
  with:
    terraform-working-directory: terraform/stacks/infra-my-app
    terraform-init-command: terraform init -input=false -backend-config="env/backend_s3_dev.hcl"
    deploy-metadata-output: my_app_deploy_metadata
    service-groups-json: '{"primary":{"service_ids":["api"]}}'
    image-uris-json: ${{ needs.collect-image-uris.outputs.image_uris_json }}
    rebuilt-service-ids-json: ${{ needs.generate-matrix.outputs.rebuilt_service_ids_json }}
    env-or-infra-changed: ${{ needs.generate-matrix.outputs.env_or_infra_changed }}

- uses: austinibele/gh-actions/.github/ecs-update-standalone-tasks@main
  if: steps.ecs-deploy.outputs.metadata_configured == 'true'
  with:
    standalone-tasks-json: '{"nightly_sync":{"task_definition_arn":"arn:aws:ecs:us-east-1:123456789012:task-definition/my-app-nightly-sync:7","image_service_id":"api","scheduled":true,"eventbridge_rule_name":"my-app-nightly-sync"}}'
    image-uris-json: ${{ needs.collect-image-uris.outputs.image_uris_json }}
    rebuilt-service-ids-json: ${{ needs.generate-matrix.outputs.rebuilt_service_ids_json }}
    env-or-infra-changed: ${{ needs.generate-matrix.outputs.env_or_infra_changed }}
```

In practice `standalone-tasks-json` is read from the deploy metadata's `standalone_tasks` in the `tf-output.json` that `ecs-deploy` wrote.

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `standalone-tasks-json` | JSON object mapping task keys to `{ task_definition_arn, image_service_id, optional?, scheduled?, eventbridge_target?, eventbridge_rule_name?, eventbridge_bus_name? }` | Yes | - |
| `image-uris-json` | JSON object of service id -> ECR image URI | Yes | - |
| `rebuilt-service-ids-json` | JSON array of service ids rebuilt in this run (accepted for caller symmetry; every task is re-registered) | Yes | - |
| `env-or-infra-changed` | `true`/`false` string (accepted for caller symmetry; every task is re-registered) | Yes | - |
