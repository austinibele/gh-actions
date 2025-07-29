#!/usr/bin/env bats

setup() {
  SCRIPT=".github/package-lambda/export-build-env.sh"
}

@test "exports variables from json array" {
  JSON='[{"name":"FOO","value":"bar"},{"name":"BAZ","value":"qux"}]'
  run bash -c "source $SCRIPT --json '$JSON' && echo \$FOO \$BAZ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"bar qux"* ]]
}

@test "no vars exported when array is empty" {
  run bash -c "source $SCRIPT --json '[]' && echo done"
  [ "$status" -eq 0 ]
  [[ "$output" == *"done"* ]]
} 