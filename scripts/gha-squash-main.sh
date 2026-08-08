#!/usr/bin/env bash
# Squash the default branch to a single commit and force-push.
# Optional: DELETE_PATHS="file1 file2" removes those paths before squash.
# Env: GH_TOKEN (or github.token), GITHUB_REPOSITORY, GIT_AUTHOR_NAME/EMAIL optional.
set -euo pipefail

REPO="${GITHUB_REPOSITORY:?}"
BRANCH="${SQUASH_BRANCH:-main}"
MSG="${SQUASH_MESSAGE:-Private WebKitGTK DnD validation CI and dual-runner burn infra}"
WORK="${SQUASH_WORK_DIR:-$HOME/webkit-dnd-squash}"
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
: "${TOKEN:?GH_TOKEN or GITHUB_TOKEN required}"

rm -rf "$WORK"
git clone --depth 1 "https://x-access-token:${TOKEN}@github.com/${REPO}.git" "$WORK"
cd "$WORK"
git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH"

if [[ -n "${DELETE_PATHS:-}" ]]; then
  # shellcheck disable=SC2086
  git rm -f $DELETE_PATHS 2>/dev/null || true
  for p in $DELETE_PATHS; do
    rm -rf "$p" 2>/dev/null || true
  done
  git add -A || true
fi

# Orphan squash — one root commit, full tree
git checkout --orphan "squash-$$"
git add -A
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-sirredbeard}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-sirredbeard@users.noreply.github.com}"
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
git -c user.name="$GIT_AUTHOR_NAME" -c user.email="$GIT_AUTHOR_EMAIL" commit \
  --message "$MSG"

# Never allow Co-authored-by trailers
if git log -1 --format=%B | grep -qi 'co-authored-by'; then
  echo "refusing commit with Co-authored-by" >&2
  exit 1
fi

git branch -M "$BRANCH"
git push --force "https://x-access-token:${TOKEN}@github.com/${REPO}.git" "HEAD:${BRANCH}"
echo "SQUASH_OK $(git rev-parse --short HEAD) count=$(git rev-list --count HEAD)"
cd /
rm -rf "$WORK"
