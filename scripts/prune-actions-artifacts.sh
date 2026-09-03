#!/usr/bin/env bash
# prune-actions-artifacts.sh
#
# Keep the newest KEEP Actions artifacts on this repo; delete the rest.
# Saves private-repo storage. Needs gh auth with actions:write (or repo admin).
#
# Usage:
#   ./scripts/prune-actions-artifacts.sh [KEEP]
# Env:
#   GH_REPO   owner/name (default: current gh repo)
#   KEEP      default 5
set -euo pipefail

KEEP="${1:-${KEEP:-5}}"
if ! [[ "$KEEP" =~ ^[0-9]+$ ]] || ((KEEP < 1)); then
  echo "usage: $0 [KEEP>=1]" >&2
  exit 2
fi
command -v gh >/dev/null || { echo "gh required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq required" >&2; exit 1; }

REPO="${GH_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
echo "=== Actions artifact prune: ${REPO} keep=${KEEP} ==="

# Paginate newest-first is not guaranteed; sort by created_at ourselves.
mapfile -t IDS < <(gh api --paginate "repos/${REPO}/actions/artifacts?per_page=100" \
  --jq '.artifacts | sort_by(.created_at) | reverse | .[].id')

TOTAL=${#IDS[@]}
echo "artifacts listed: ${TOTAL}"
if ((TOTAL <= KEEP)); then
  echo "nothing to delete"
  exit 0
fi

fail=0
i=0
for id in "${IDS[@]}"; do
  if ((i < KEEP)); then
    echo "keep id=${id}"
  else
    echo "delete id=${id}"
    if ! gh api --method DELETE "repos/${REPO}/actions/artifacts/${id}"; then
      echo "  WARN: delete failed id=${id}" >&2
      fail=1
    fi
  fi
  i=$((i + 1))
done

if ((fail != 0)); then
  echo "prune-actions-artifacts: some deletes failed" >&2
  exit 1
fi
echo "=== Actions artifact prune done ==="
