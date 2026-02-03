# Build Decision Action

Artifact-agnostic build decision logic using S3 ledger, change detection, and previous run status. Works with any artifact type (Docker images, Lambda functions, static sites, etc.).

## Features

- **S3-based ledger** - Tracks build status across workflow runs
- **Change detection** - Filters changes by glob patterns
- **Previous run check** - Rebuilds if previous run failed
- **Force build** - Override all checks when needed

## Usage

```yaml
- uses: austinibele/gh-actions/.github/build-decision@v1
  id: decision
  with:
    artifact_id: backend
    filter_patterns: '["crm/backend/**", "common/**", "package.json"]'
    s3_bucket: ${{ env.S3_TERRAFORM_ARTIFACTS_BUCKET_NAME }}

- name: Build and push image
  if: steps.decision.outputs.should_build == 'true'
  run: |
    echo "Building because: ${{ steps.decision.outputs.reason }}"
    docker build -t $IMAGE_TAG .
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `artifact_id` | Unique identifier for the artifact | Yes | - |
| `filter_patterns` | JSON array of glob patterns to watch | Yes | - |
| `s3_bucket` | S3 bucket for ledger storage | Yes | - |
| `ledger_prefix` | S3 key prefix for ledger files | No | `build-ledger/` |
| `check_previous_run` | Check if previous workflow run failed | No | `true` |
| `job_pattern` | Pattern to match job name for previous run check | No | `artifact_id` |
| `force_build` | Force rebuild regardless of checks | No | `false` |

## Outputs

| Output | Description |
|--------|-------------|
| `should_build` | `"true"` or `"false"` |
| `reason` | One of: `source_changed`, `previous_failed`, `ledger_missing`, `ledger_failed`, `forced`, `no_changes` |
| `last_success_sha` | SHA of last successful build |
| `changed_files` | List of changed files (if any) |

## Decision Matrix

| Ledger Status | Source Changed | Previous Failed | Result |
|---------------|----------------|-----------------|--------|
| missing | * | * | build (reason: `ledger_missing`) |
| failure | * | * | build (reason: `ledger_failed`) |
| success | true | * | build (reason: `source_changed`) |
| success | false | true | build (reason: `previous_failed`) |
| success | false | false | skip (reason: `no_changes`) |

## Examples

### Docker Image Build

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: austinibele/gh-actions/.github/build-decision@v1
        id: decision
        with:
          artifact_id: backend
          filter_patterns: '["crm/backend/**", "common/**"]'
          s3_bucket: my-bucket

      - name: Build image
        if: steps.decision.outputs.should_build == 'true'
        run: docker build -t backend:${{ github.sha }} .

      - uses: austinibele/gh-actions/.github/ledger@v1
        if: always()
        with:
          action: write
          artifact_id: backend
          status: ${{ job.status == 'success' && 'success' || 'failure' }}
          s3_bucket: my-bucket
```

### Lambda Package

```yaml
- uses: austinibele/gh-actions/.github/build-decision@v1
  id: lambda-decision
  with:
    artifact_id: slack-notifier-lambda
    filter_patterns: '["python/slack-notifier/**"]'
    s3_bucket: my-artifacts-bucket

- name: Package Lambda
  if: steps.lambda-decision.outputs.should_build == 'true'
  run: |
    cd python/slack-notifier
    zip -r lambda.zip .
    aws s3 cp lambda.zip s3://$BUCKET/$KEY
```

## Required IAM Permissions

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject"],
  "Resource": "arn:aws:s3:::BUCKET/build-ledger/*"
}
```

## Filter Patterns

The `filter_patterns` input accepts a JSON array of glob patterns:

- `"src/**"` - Matches all files under `src/` directory
- `"package.json"` - Exact file match
- `"*.ts"` - Matches all `.ts` files in root

Example:
```yaml
filter_patterns: '["crm/backend/**", "common/**", "package.json", "pnpm-lock.yaml"]'
```
