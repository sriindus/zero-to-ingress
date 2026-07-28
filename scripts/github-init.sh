#!/usr/bin/env bash
# Create the GitHub repo and push this project to it.
# Requires the GitHub CLI (gh) — install with: brew install gh && gh auth login
set -euo pipefail

cd "$(dirname "$0")/.."

REPO_NAME="${REPO_NAME:-hello-world-k8s}"
VISIBILITY="${VISIBILITY:-public}"   # public | private

command -v gh >/dev/null 2>&1 || {
  echo "gh not found. Install it: brew install gh && gh auth login" >&2
  exit 1
}

if [[ ! -d .git ]]; then
  echo "==> initializing git repository"
  git init -b main
fi

git add -A
git diff --cached --quiet || git commit -m "Hello World Node.js front end with Docker, Kubernetes and Jenkins pipeline"

if git remote get-url origin >/dev/null 2>&1; then
  echo "==> origin already set: $(git remote get-url origin)"
  git push -u origin main
else
  echo "==> creating $VISIBILITY repo '$REPO_NAME' and pushing"
  gh repo create "$REPO_NAME" "--$VISIBILITY" --source=. --remote=origin --push
fi

echo "==> done: $(git remote get-url origin)"
