#shellspec
# Tests for check-registry.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPT_UNDER_TEST="${SCRIPT_DIR}/../../.github/npm-publish/check-registry.sh"

Describe 'check-registry.sh'

  It 'sets should_publish=false when the version exists in the registry'
    When run bash -c '
      work=$(mktemp -d)
      stub=$(mktemp -d)
      printf "%s\n" "{" "  \"name\": \"@scope/pkg\"" "}" > "$work/package.json"
      cat > "$stub/npm" <<'\''EOF'\''
#!/usr/bin/env bash
echo "1.2.3"
exit 0
EOF
      chmod +x "$stub/npm"
      cd "$work"
      export PATH="$stub:$PATH"
      export PACKAGE_VERSION="1.2.3"
      export REGISTRY_URL="https://npm.pkg.github.com"
      export NODE_AUTH_TOKEN="test-token"
      export GITHUB_OUTPUT
      GITHUB_OUTPUT=$(mktemp)
      bash "$SCRIPT_UNDER_TEST"
      cat "$GITHUB_OUTPUT"
    '
    The output should include "Version already exists (@scope/pkg@1.2.3); skipping publish."
    The output should include "should_publish=false"
  End

  It 'sets should_publish=true when npm view reports 404'
    When run bash -c '
      work=$(mktemp -d)
      stub=$(mktemp -d)
      printf "%s\n" "{" "  \"name\": \"@scope/pkg\"" "}" > "$work/package.json"
      cat > "$stub/npm" <<'\''EOF'\''
#!/usr/bin/env bash
echo "npm error 404 Not Found - GET https://npm.pkg.github.com/@scope%2fpkg" >&2
exit 1
EOF
      chmod +x "$stub/npm"
      cd "$work"
      export PATH="$stub:$PATH"
      export PACKAGE_VERSION="1.2.3"
      export REGISTRY_URL="https://npm.pkg.github.com"
      export NODE_AUTH_TOKEN="test-token"
      export GITHUB_OUTPUT
      GITHUB_OUTPUT=$(mktemp)
      bash "$SCRIPT_UNDER_TEST"
      cat "$GITHUB_OUTPUT"
    '
    The output should include "Version does not exist in registry yet."
    The output should include "should_publish=true"
  End

  It 'sets should_publish=true when npm view fails with non-404 stderr'
    When run bash -c '
      work=$(mktemp -d)
      stub=$(mktemp -d)
      printf "%s\n" "{" "  \"name\": \"@scope/pkg\"" "}" > "$work/package.json"
      cat > "$stub/npm" <<'\''EOF'\''
#!/usr/bin/env bash
echo "npm error E401 Unable to authenticate" >&2
exit 1
EOF
      chmod +x "$stub/npm"
      cd "$work"
      export PATH="$stub:$PATH"
      export PACKAGE_VERSION="1.2.3"
      export REGISTRY_URL="https://npm.pkg.github.com"
      export NODE_AUTH_TOKEN="test-token"
      export GITHUB_OUTPUT
      GITHUB_OUTPUT=$(mktemp)
      bash "$SCRIPT_UNDER_TEST"
      cat "$GITHUB_OUTPUT"
    '
    The output should include "npm view returned a non-404 response; continuing with publish attempt."
    The output should include "npm error E401 Unable to authenticate"
    The output should include "should_publish=true"
  End

End
