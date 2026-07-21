# gh-ci-templates

Reusable GitHub Actions workflows + a bootstrap script, so setting up CI /
semantic-release / branch policy on a new repo is a 2-minute job instead of
copy-pasting and re-debugging YAML every time.

Convention this repo standardizes on:

- `develop` is the integration branch. `feature/*`, `fix/*`, `chore/*`,
  `docs/*`, `refactor/*`, `test/*`, `perf/*`, `ci/*`, `build/*`,
  `dependabot/*` branches merge into it via **squash merge**.
- `main` is the stable branch. `develop` merges into it via a real **merge
  commit** (not squash), so `main` keeps the full, granular commit history
  instead of one opaque "merge to main" commit per release.
- Releases are handled by [semantic-release](https://semantic-release.gitbook.io/),
  triggered on every push to `main`/`develop`, versioning from
  [Conventional Commits](https://www.conventionalcommits.org/).

## Quick start (new repo)

From inside the repo you want to set up (already pushed to GitHub, `gh` CLI
authenticated with admin rights on it):

```bash
curl -fsSL https://raw.githubusercontent.com/Flaykz/gh-ci-templates/main/bootstrap.sh | bash
# or, to also publish a Docker image to GHCR on release:
curl -fsSL https://raw.githubusercontent.com/Flaykz/gh-ci-templates/main/bootstrap.sh | bash -s -- --docker
```

This downloads the wrapper workflows + config templates into the repo,
creates `develop` if missing, sets the merge methods (squash + merge commit,
no rebase), and applies branch protection on `main`/`develop` with the
correct required status checks.

It prints a short list of remaining manual steps (install semantic-release +
commitlint packages, add the `ci`/`release` npm scripts, register the
`DEVELOP_SYNC_TOKEN` secret) — these touch `package.json` and repo secrets,
which the script deliberately doesn't do for you.

## What's in here

- `.github/workflows/ci.yml` — reusable `workflow_call`: lint, typecheck,
  build. Inputs let you override the commands if a repo doesn't use plain
  npm scripts.
- `.github/workflows/branch-policy.yml` — reusable `workflow_call`: enforces
  the branch flow above on every PR.
- `.github/workflows/release.yml` — reusable `workflow_call`: runs
  semantic-release, temporarily lifts branch protection for the release
  commit, syncs the stable `main` release version back onto `develop`, and
  optionally builds/pushes a Docker image to GHCR.
- `templates/workflows/*.yml` — the thin wrapper files a consuming repo
  actually commits (each just a few lines that `uses:` the reusable workflow
  above). `bootstrap.sh` copies these in for you.
- `templates/release.config.cjs`, `templates/commitlint.config.cjs` —
  starter configs. Copied in only if the target repo doesn't already have
  one.
- `bootstrap.sh` — see Quick start above.

## Why release commits use `[release-sync]`, not `[skip ci]`

`@semantic-release/git` commits are tagged in their message so the
release workflow doesn't loop on its own push. Do **not** use GitHub's
native `[skip ci]` (or `[ci skip]`, `[no ci]`, `[skip actions]`,
`[actions skip]`) for this: GitHub silently drops *every* workflow run —
push **and** pull_request — tied to a commit matching one of those, which
means any PR whose head lands on that commit (e.g. every `develop -> main`
PR, since `develop`'s tip is always a release commit) never gets its checks
triggered, and looks permanently stuck. The templates here use a custom
`[release-sync]` marker instead, which only the release workflow's own
job-level `if:` guard checks for.

## Updating the pipeline for every consuming repo at once

Wrapper files pin `@main`, so fixing a bug here (like the `[skip ci]` one
above) or improving a step applies to every repo that consumes it on their
next workflow run — no per-repo file edits needed. Pin to a tag/SHA instead
of `@main` if you want opt-in upgrades per repo.

## Required repo secret

`release.yml` needs a `DEVELOP_SYNC_TOKEN`: a fine-grained PAT with
`Contents` + `Administration` read/write on the target repo. It's used to
temporarily lift branch protection for the release commit and to push the
version-sync commit back to `develop`. Without it, the release job fails
closed (loudly) rather than silently doing nothing.
