#!/usr/bin/env bats

setup() {
  script=".github/build-image/validate-build-args.sh"
  ok_dockerfile="tests/build-image/fixtures/Dockerfile.OK"
}

@test "passes when all args are declared" {
  run bash "$script" --dockerfile "$ok_dockerfile" --build-args $'FOO=one\nBAR=two'
  [ "$status" -eq 0 ]
  [[ "$output" == *"All build arguments"* ]]
}

@test "fails when an arg is missing" {
  run bash "$script" --dockerfile "$ok_dockerfile" --build-args "MISSING=value"
  [ "$status" -ne 0 ]
  [[ "$output" == *"MISSING"* ]]
} 