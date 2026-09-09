#shellspec
# Tests for detect-release.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_UNDER_TEST="${SCRIPT_DIR}/../../.github/npm-publish/detect-release.sh"

Describe 'detect-release.sh'

  It 'sets should_release=true when no prior chore(release): v commit exists'
    When run bash -c '
      set -euo pipefail
      repo=$(mktemp -d)
      cd "$repo"
      git init -q --template=
      git config user.name "test"
      git config user.email "test@example.com"
      echo ok > README.md
      git add README.md
      git commit -q -m "initial"
      export RELEASE_PATHS="package.json src/"
      export GITHUB_OUTPUT
      GITHUB_OUTPUT=$(mktemp)
      bash "$SCRIPT_UNDER_TEST"
      cat "$GITHUB_OUTPUT"
    '
    The output should include "No previous release bump commit found. Releasing."
    The output should include "should_release=true"
  End

  It 'sets should_release=false when a prior release commit exists and RELEASE_PATHS is unchanged'
    When run bash -c '
      set -euo pipefail
      repo=$(mktemp -d)
      cd "$repo"
      git init -q --template=
      git config user.name "test"
      git config user.email "test@example.com"
      echo "{\"name\":\"pkg\",\"version\":\"1.0.0\"}" > package.json
      mkdir -p src
      echo src > src/index.ts
      git add package.json src/index.ts
      git commit -q -m "chore(release): v1.0.0 [skip ci]"
      echo notes > README.md
      git add README.md
      git commit -q -m "docs: readme"
      export RELEASE_PATHS="package.json src/"
      export GITHUB_OUTPUT
      GITHUB_OUTPUT=$(mktemp)
      bash "$SCRIPT_UNDER_TEST"
      cat "$GITHUB_OUTPUT"
    '
    The output should include "should_release=false"
    The output should include "Skipping release."
  End

  It 'sets should_release=true when a prior release commit exists and RELEASE_PATHS changed'
    When run bash -c '
      set -euo pipefail
      repo=$(mktemp -d)
      cd "$repo"
      git init -q --template=
      git config user.name "test"
      git config user.email "test@example.com"
      echo "{\"name\":\"pkg\",\"version\":\"1.0.0\"}" > package.json
      mkdir -p src
      echo src > src/index.ts
      git add package.json src/index.ts
      git commit -q -m "chore(release): v1.0.0 [skip ci]"
      echo src2 > src/index.ts
      git add src/index.ts
      git commit -q -m "feat: change source"
      export RELEASE_PATHS="package.json src/"
      export GITHUB_OUTPUT
      GITHUB_OUTPUT=$(mktemp)
      bash "$SCRIPT_UNDER_TEST"
      cat "$GITHUB_OUTPUT"
    '
    The output should include "Releasable changes found:"
    The output should include "src/index.ts"
    The output should include "should_release=true"
  End

End
