# NPM Publish Action

Detect releasable changes since the last `chore(release): v` commit, bump the package version, skip if that version already exists in the registry, publish, and push the bump commit.

The default publish command is `pnpm publish` because only pnpm applies `publishConfig` entrypoint overrides (for example swapping `exports` to `dist/` at publish time). Use `publish_command` only when you intentionally want a different client.

## Usage

```yaml
name: Publish Package

on:
  push:
    branches:
      - main

permissions:
  contents: write
  packages: write

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0

      - uses: pnpm/action-setup@v4
        with:
          version: 10
          run_install: false

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          registry-url: https://npm.pkg.github.com
          scope: '@myvisausa'
          cache: pnpm

      - run: pnpm install --frozen-lockfile
      - run: pnpm run build
      - run: pnpm run typecheck
      - run: pnpm run test

      - uses: austinibele/gh-actions/.github/npm-publish@main
        with:
          release_paths: package.json pnpm-lock.yaml tsconfig.json tsconfig.build.json src/
          token: ${{ secrets.GITHUB_TOKEN }}
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `release_paths` | Space-separated git pathspecs for `git diff --name-only <last_release>..HEAD` | Yes | - |
| `token` | Exported as `NODE_AUTH_TOKEN` for `npm view` / publish | Yes | - |
| `registry_url` | npm registry URL (appended as `--registry`) | No | `https://npm.pkg.github.com` |
| `publish_command` | Publish command; `--registry <registry_url>` is appended | No | `pnpm publish --access restricted --no-git-checks` |
| `bump` | Argument to `npm version --no-git-tag-version` | No | `patch` |
| `release_branch` | Remote branch for `git push origin HEAD:<branch>` | No | `main` |

## Outputs

| Output | Description |
|--------|-------------|
| `released` | `"true"` if a package was published, otherwise `"false"` |
| `version` | Bumped package version when a release was attempted |
