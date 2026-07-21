#!/usr/bin/env bash
# Bootstrap script for Flaykz/gh-ci-templates.
#
# Run from inside the target repo's working directory. The repo must already
# exist on GitHub (origin configured) and you need an authenticated `gh` CLI
# with admin rights on it.
#
# Usage:
#   ./bootstrap.sh            # standard setup, no Docker publish
#   ./bootstrap.sh --docker   # also enable GHCR image publish on release
#
# What it does:
#   1. Downloads the CI / branch-policy / release wrapper workflows and the
#      semantic-release / commitlint config templates into this repo.
#   2. Makes sure a `develop` branch exists.
#   3. Enables squash-merge (for feature/fix/chore -> develop) and merge-commit
#      (for develop -> main) at the repo level.
#   4. Applies branch protection on main and develop with the required status
#      checks that match the wrapper workflows' job names.
#
# What it does NOT do (must be done by hand, see the printed next steps):
#   - install the semantic-release / commitlint npm packages
#   - add the "release"/"ci" npm scripts
#   - create and register the DEVELOP_SYNC_TOKEN secret

set -euo pipefail

TEMPLATES_REPO="Flaykz/gh-ci-templates"
TEMPLATES_REF="main"
MAIN_BRANCH="main"
DEVELOP_BRANCH="develop"
PUBLISH_DOCKER="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --docker) PUBLISH_DOCKER="true"; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Run this from inside a git repository (with 'origin' pointing at GitHub)." >&2
  exit 1
fi

REPO_SLUG="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
echo "==> Bootstrapping CI for $REPO_SLUG"

RAW_BASE="https://raw.githubusercontent.com/$TEMPLATES_REPO/$TEMPLATES_REF"

echo "==> Fetching workflow templates"
mkdir -p .github/workflows
curl -fsSL "$RAW_BASE/templates/workflows/ci.yml" -o .github/workflows/ci.yml
curl -fsSL "$RAW_BASE/templates/workflows/branch-policy.yml" -o .github/workflows/branch-policy.yml
curl -fsSL "$RAW_BASE/templates/workflows/release.yml" -o .github/workflows/release.yml

if [[ "$PUBLISH_DOCKER" == "true" ]]; then
  sed -i.bak 's/publish-docker: false/publish-docker: true/' .github/workflows/release.yml
  rm -f .github/workflows/release.yml.bak
fi

echo "==> Fetching config templates"
if [[ ! -f release.config.cjs ]]; then
  curl -fsSL "$RAW_BASE/templates/release.config.cjs" -o release.config.cjs
else
  echo "    release.config.cjs already exists, leaving it untouched"
fi

if [[ ! -f commitlint.config.cjs ]]; then
  curl -fsSL "$RAW_BASE/templates/commitlint.config.cjs" -o commitlint.config.cjs
else
  echo "    commitlint.config.cjs already exists, leaving it untouched"
fi

echo "==> Making sure '$DEVELOP_BRANCH' exists"
git fetch origin >/dev/null 2>&1 || true
if ! git ls-remote --exit-code --heads origin "$DEVELOP_BRANCH" >/dev/null 2>&1; then
  git branch "$DEVELOP_BRANCH" 2>/dev/null || true
  git push -u origin "$DEVELOP_BRANCH"
else
  echo "    already exists on origin"
fi

echo "==> Setting merge methods (squash + merge commit, rebase disabled)"
gh repo edit "$REPO_SLUG" --enable-squash-merge --enable-merge-commit --enable-rebase-merge=false >/dev/null

echo "==> Applying branch protection"
CONTEXTS='["checks / Lint, typecheck, build","validate-source-branch / Validate source branch"]'

protect() {
  local branch="$1" linear_history="$2"
  gh api -X PUT "repos/$REPO_SLUG/branches/$branch/protection" --input - <<JSON
{
  "required_status_checks": { "strict": true, "contexts": $CONTEXTS },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": false,
    "require_code_owner_reviews": false,
    "required_approving_review_count": 0,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_linear_history": $linear_history,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false
}
JSON
}

# develop stays linear (squash-only, feature/fix/chore branches land here).
# main allows merge commits (develop -> main keeps its full commit history).
protect "$DEVELOP_BRANCH" true
protect "$MAIN_BRANCH" false

cat <<EOF

==> Done. Remaining manual steps:

1. Install the release tooling:
   npm install -D semantic-release @semantic-release/commit-analyzer \\
     @semantic-release/release-notes-generator @semantic-release/npm \\
     @semantic-release/git @semantic-release/github @semantic-release/exec \\
     conventional-changelog-conventionalcommits \\
     @commitlint/cli @commitlint/config-conventional

2. Add these npm scripts to package.json:
   "lint": "...", "typecheck": "...", "build": "...",
   "ci": "npm run lint && npm run typecheck && npm run build",
   "release": "semantic-release"

3. Create a fine-grained PAT (repo scope: Contents + Administration, both
   read/write) and register it as the release secret:
   gh secret set DEVELOP_SYNC_TOKEN --repo $REPO_SLUG

4. Commit and push:
   git add .github release.config.cjs commitlint.config.cjs
   git commit -m "ci: bootstrap shared CI/release pipeline"
   git push

For develop -> main PRs, merge with "Create a merge commit", not squash —
main's branch protection now allows it and develop's still requires linear
history, so squash stays the only option for feature/fix/chore -> develop.
EOF
