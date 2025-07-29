#!/usr/bin/env bats

setup() {
  SCRIPT=".github/package-lambda/determine-env-and-key.sh"
}

@test "main branch produces prod tag and keys" {
  run bash "$SCRIPT" --branch main --key-prefix mylambda --sha abc123
  [ "$status" -eq 0 ]
  [[ "$output" == *"env_tag=prod"* ]]
  [[ "$output" == *"s3_prefix=mylambda-prod"* ]]
  [[ "$output" == *"s3_key=mylambda-prod-abc123.zip"* ]]
}

@test "non-main branch produces dev tag and keys" {
  run bash "$SCRIPT" --branch feature/foo --key-prefix mylambda --sha def456
  [ "$status" -eq 0 ]
  [[ "$output" == *"env_tag=dev"* ]]
  [[ "$output" == *"s3_prefix=mylambda-dev"* ]]
  [[ "$output" == *"s3_key=mylambda-dev-def456.zip"* ]]
} 