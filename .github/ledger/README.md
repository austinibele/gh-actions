# Ledger Action

S3-based build status tracking for CI workflows. Records and retrieves build status to enable smart rebuild decisions.

## Features

- **Check operation** - Retrieve build status for an artifact
- **Write operation** - Record build status after completion
- **Configurable prefix** - Organize ledger files by project/environment

## Usage

### Check if build is needed

```yaml
- uses: austinibele/gh-actions/.github/ledger@v1
  id: ledger
  with:
    action: check
    artifact_id: backend
    s3_bucket: ${{ env.S3_TERRAFORM_ARTIFACTS_BUCKET_NAME }}

- name: Build if needed
  if: steps.ledger.outputs.should_build == 'true'
  run: docker build -t backend:${{ github.sha }} .
```

### Record build status

```yaml
- uses: austinibele/gh-actions/.github/ledger@v1
  if: always()
  with:
    action: write
    artifact_id: backend
    status: ${{ job.status == 'success' && 'success' || 'failure' }}
    s3_bucket: ${{ env.S3_TERRAFORM_ARTIFACTS_BUCKET_NAME }}
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `action` | Action to perform: `check` or `write` | Yes | - |
| `artifact_id` | Unique identifier for the artifact | Yes | - |
| `s3_bucket` | S3 bucket for ledger storage | Yes | - |
| `ledger_prefix` | S3 key prefix for ledger files | No | `build-ledger/` |
| `sha` | Commit SHA | No | `GITHUB_SHA` |
| `status` | Build status for write: `success`, `failure`, or `building` | For write | - |

## Outputs

| Output | Description |
|--------|-------------|
| `should_build` | For check action: `"true"` or `"false"` |
| `last_success_sha` | For check action: SHA of last successful build |

## Ledger File Format

The ledger stores JSON files in S3 at `s3://{bucket}/{prefix}{artifact_id}.json`:

```json
{
  "artifact_id": "backend",
  "status": "success",
  "last_attempt_sha": "abc123",
  "last_attempt_ts": "2024-01-15T10:30:00Z",
  "last_success_sha": "abc123",
  "last_success_ts": "2024-01-15T10:30:00Z"
}
```

## Check Logic

The check action returns `should_build=true` when:
- Ledger file is missing (first build)
- Status is `failure` or `building`

Returns `should_build=false` when:
- Status is `success` (defer to change detection)

## Complete Example

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: us-east-1

      # Check ledger and changes
      - uses: austinibele/gh-actions/.github/build-decision@v1
        id: decision
        with:
          artifact_id: backend
          filter_patterns: '["src/**"]'
          s3_bucket: my-bucket

      # Build if needed
      - name: Build
        if: steps.decision.outputs.should_build == 'true'
        run: docker build -t backend:${{ github.sha }} .

      # Always update ledger
      - uses: austinibele/gh-actions/.github/ledger@v1
        if: always()
        with:
          action: write
          artifact_id: backend
          status: ${{ job.status == 'success' && 'success' || 'failure' }}
          s3_bucket: my-bucket
```

## Required IAM Permissions

```json
{
  "Effect": "Allow",
  "Action": ["s3:GetObject", "s3:PutObject"],
  "Resource": "arn:aws:s3:::BUCKET/build-ledger/*"
}
```
