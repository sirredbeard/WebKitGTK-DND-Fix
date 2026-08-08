#!/usr/bin/env bash
# Find the newest Actions artifact named webkitgtk-prefix-* for this repo,
# optionally matching a WebKit SHA prefix in the artifact name.
# Prints: RUN_ID<TAB>ARTIFACT_NAME
set -euo pipefail

OWNER_REPO="${OWNER_REPO:-${GH_REPO:-}}"
SHA_PREFIX="${1:-}"
LIMIT="${LIMIT:-30}"

if [[ -z "${OWNER_REPO}" ]]; then
  OWNER_REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)"
fi
[[ -n "${OWNER_REPO}" ]] || { echo "set GH_REPO or OWNER_REPO" >&2; exit 1; }

# List recent artifacts (paginated lightly)
mapfile -t rows < <(
  gh api --paginate \
    "/repos/${OWNER_REPO}/actions/artifacts?per_page=100" \
    --jq '.artifacts[] | select(.expired|not) | select(.name|test("^webkitgtk-prefix")) | [.id, .name, .workflow_run.id // 0, .created_at] | @tsv' \
    2>/dev/null | head -n 500 || true
)

if ((${#rows[@]} == 0)); then
  echo "none" >&2
  exit 1
fi

best=""
best_ts=""
for row in "${rows[@]}"; do
  # id name run_id created_at
  IFS=$'\t' read -r aid aname run_id created <<<"${row}"
  if [[ -n "${SHA_PREFIX}" && "${aname}" != *"${SHA_PREFIX}"* ]]; then
    continue
  fi
  if [[ -z "${best_ts}" || "${created}" > "${best_ts}" ]]; then
    best_ts="${created}"
    best="${run_id}	${aname}	${aid}"
  fi
done

if [[ -z "${best}" ]]; then
  echo "none matching ${SHA_PREFIX}" >&2
  exit 1
fi
printf '%s\n' "${best}"
