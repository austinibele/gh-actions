#shellspec
Describe 'Command-scoped GitHub authentication'
  It 'preserves credential scope and propagates authentication to child Git'
    When run python3 "${SHELLSPEC_PROJECT_ROOT}/tests/github/test_github_git.py"
    The status should be success
    The stderr should include 'OK'
  End
End
