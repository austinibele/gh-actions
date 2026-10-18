# Lambda Container Deploy Action

Points the container-image Lambda functions in a Terraform deploy metadata output at their new ECR images with `lambda update-function-code`, then polls `lambda get-function` until each update is `Successful`; a `Failed` update or one still unfinished after `update-max-polls` checks fails the step, so a deployment ledger written afterwards records a real rollout. It reads the metadata's `lambda_functions` map (`{ <key>: { function_name, image_service_id } }`), or a legacy single `lambda` entry when exactly one expected mapping is given, and fails when an expected Lambda is missing or has a different `image_service_id`. A Lambda is updated when its image service was rebuilt in this run, or when deploy/env or infra changed and the workflow owns its image (it is expected or has an image URI); otherwise it is skipped, including images another pipeline builds and deploys. Call it after `ecs-deploy`, in the same job and with the same AWS credentials, with `terraform-working-directory` set to the directory where `ecs-deploy` wrote `tf-output.json`.

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

- uses: austinibele/gh-actions/.github/lambda-container-deploy@main
  if: steps.ecs-deploy.outputs.metadata_configured == 'true'
  with:
    terraform-working-directory: terraform/stacks/infra-my-app
    deploy-metadata-output: my_app_deploy_metadata
    expected-lambda-functions-json: '{"ssr":{"image_service_id":"ssr"}}'
    image-uris-json: ${{ needs.collect-image-uris.outputs.image_uris_json }}
    rebuilt-service-ids-json: ${{ needs.generate-matrix.outputs.rebuilt_service_ids_json }}
    env-or-infra-changed: ${{ needs.generate-matrix.outputs.env_or_infra_changed }}
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `terraform-working-directory` | Terraform stack directory; the step runs here and reads `tf-output.json` | Yes | - |
| `deploy-metadata-output` | Terraform output name for the deploy metadata JSON | Yes | - |
| `image-uris-json` | JSON object of service id -> ECR image URI | Yes | - |
| `rebuilt-service-ids-json` | JSON array of service ids rebuilt in this run | Yes | - |
| `env-or-infra-changed` | `true`/`false` string: deploy/env or infra paths changed | Yes | - |
| `expected-lambda-functions-json` | JSON object of the Lambda keys this workflow owns -> `{ image_service_id }` | No | `{}` |
| `update-poll-seconds` | Seconds between `get-function` checks | No | `5` |
| `update-max-polls` | `get-function` checks before an unfinished update fails | No | `60` |
