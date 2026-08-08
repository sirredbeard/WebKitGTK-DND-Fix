#!/usr/bin/env bash
# Exactly one disk snapshot of the Vultr burn VPS, then delete the instance.
# Snapshots cost storage — never create a second one; reuse if already pending/complete.
# Must run on Azure so API egress is the reserved allowlisted IP.
set -euo pipefail
export PATH=/usr/local/bin:/usr/bin:/bin

LOG="${VULTR_TEARDOWN_LOG:-/var/log/webkit-dnd-vultr-snapshot-delete.log}"
STAMP_DIR="${VULTR_TEARDOWN_STAMP_DIR:-/var/cache/webkit-dnd/out}"
DONE_STAMP="${STAMP_DIR}/vultr-teardown-done"
SNAP_ID_FILE="${STAMP_DIR}/vultr-teardown-snapshot-id"
EXPECTED_IP="${AZURE_STATIC_IP:-20.127.61.97}"
INSTANCE_ID="${VULTR_INSTANCE_ID:-3f9688ab-29c8-440a-a13e-ad6ded14792d}"
# Stable description so retries find the same snapshot instead of minting another.
SNAP_DESC="${VULTR_SNAPSHOT_DESC:-webkit-dnd-gha-final}"
WAIT_MINUTES="${VULTR_SNAPSHOT_WAIT_MINUTES:-120}"

mkdir -p "$STAMP_DIR" "$(dirname "$LOG")"
exec >>"$LOG" 2>&1
echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) start instance=$INSTANCE_ID desc=$SNAP_DESC ===="

if [[ -f "$DONE_STAMP" ]]; then
  echo "already done ($(cat "$DONE_STAMP")); no-op"
  exit 0
fi

if [[ -f /etc/webkit-dnd/vultr.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source /etc/webkit-dnd/vultr.env
  set +a
elif [[ -f /root/.config/vultr/api_key ]]; then
  export VULTR_API_KEY
  VULTR_API_KEY=$(cat /root/.config/vultr/api_key)
fi
: "${VULTR_API_KEY:?missing VULTR_API_KEY}"

# Egress must be Azure reserved IP (Vultr user API allowlist).
EGRESS=$(curl -4 -fsS --max-time 15 ifconfig.me || curl -4 -fsS --max-time 15 icanhazip.com || true)
EGRESS=$(echo "${EGRESS:-}" | tr -d '[:space:]')
echo "egress_ip=${EGRESS} expected=${EXPECTED_IP}"
if [[ "$EGRESS" != "$EXPECTED_IP" ]]; then
  echo "REFUSE: Vultr API must egress from ${EXPECTED_IP}, got ${EGRESS:-unknown}" >&2
  exit 1
fi

if ! vultr-cli instance get "$INSTANCE_ID" >/tmp/vultr-inst.txt 2>&1; then
  echo "instance already gone or unreachable — mark done, do not snapshot"
  cat /tmp/vultr-inst.txt || true
  date -u +%Y-%m-%dT%H:%M:%SZ >"$DONE_STAMP"
  echo "gone" >>"$DONE_STAMP"
  exit 0
fi
cat /tmp/vultr-inst.txt

# --- find existing single snapshot by stable description (or saved id) ---
find_snapshot() {
  python3 - "$SNAP_DESC" "${1:-}" <<'PY'
import json, sys, subprocess
desc = sys.argv[1]
want_id = sys.argv[2] if len(sys.argv) > 2 else ""
try:
    raw = subprocess.check_output(["vultr-cli", "snapshot", "list", "-o", "json"], text=True)
    d = json.loads(raw)
except Exception as e:
    print(f"list_error:{e}", file=sys.stderr)
    sys.exit(0)
snaps = d if isinstance(d, list) else d.get("snapshots") or d.get("snapshot") or []
if isinstance(snaps, dict):
    snaps = [snaps]
match = None
for s in snaps:
    sid = str(s.get("id") or s.get("snapshot_id") or "")
    sdesc = s.get("description") or ""
    if want_id and sid == want_id:
        match = s
        break
    if sdesc == desc or desc in sdesc:
        match = s
        break
if not match:
    sys.exit(0)
sid = match.get("id") or match.get("snapshot_id") or ""
status = match.get("status") or match.get("SnapshotStatus") or ""
print(f"{sid}\t{status}")
PY
}

SNAP_ID=""
if [[ -f "$SNAP_ID_FILE" ]]; then
  SNAP_ID=$(tr -d '[:space:]' <"$SNAP_ID_FILE" || true)
fi

FOUND=$(find_snapshot "$SNAP_ID" || true)
if [[ -n "$FOUND" ]]; then
  SNAP_ID=$(echo "$FOUND" | awk -F'\t' '{print $1}')
  STATUS=$(echo "$FOUND" | awk -F'\t' '{print $2}')
  echo "reusing existing snapshot id=$SNAP_ID status=$STATUS (no second snapshot)"
else
  echo "creating single snapshot description=$SNAP_DESC instance=$INSTANCE_ID"
  # Prefer JSON; fall back to plain. Only ONE create call.
  set +e
  OUT=$(vultr-cli snapshot create --instance-id "$INSTANCE_ID" --description "$SNAP_DESC" -o json 2>&1)
  rc=$?
  if [[ $rc -ne 0 ]]; then
    OUT=$(vultr-cli snapshot create --id "$INSTANCE_ID" --description "$SNAP_DESC" -o json 2>&1)
    rc=$?
  fi
  if [[ $rc -ne 0 ]]; then
    OUT=$(vultr-cli snapshot create -i "$INSTANCE_ID" -d "$SNAP_DESC" -o json 2>&1)
    rc=$?
  fi
  set -e
  echo "$OUT"
  if [[ $rc -ne 0 ]]; then
    # Race: timer + GHA both tried create; re-list by description
    FOUND=$(find_snapshot "" || true)
    if [[ -z "$FOUND" ]]; then
      echo "snapshot create failed and none found" >&2
      exit 1
    fi
  else
    SNAP_ID=$(echo "$OUT" | python3 -c "import sys,json,re
t=sys.stdin.read()
try:
 d=json.loads(t); s=d.get('snapshot',d) if isinstance(d,dict) else d
 if isinstance(s,list): s=s[0]
 print(s.get('id') or s.get('snapshot_id') or '')
except Exception:
 m=re.search(r'[0-9a-fA-F-]{36}', t); print(m.group(0) if m else '')
" 2>/dev/null || true)
    if [[ -z "$SNAP_ID" ]]; then
      FOUND=$(find_snapshot "" || true)
      SNAP_ID=$(echo "$FOUND" | awk -F'\t' '{print $1}')
    fi
  fi
  STATUS=$(echo "${FOUND:-}" | awk -F'\t' '{print $2}')
fi

[[ -n "$SNAP_ID" ]] || { echo "no snapshot id" >&2; exit 1; }
echo "$SNAP_ID" >"$SNAP_ID_FILE"
echo "waiting for snapshot $SNAP_ID (max ${WAIT_MINUTES}m)"

deadline=$((SECONDS + WAIT_MINUTES * 60))
while (( SECONDS < deadline )); do
  FOUND=$(find_snapshot "$SNAP_ID" || true)
  STATUS=$(echo "$FOUND" | awk -F'\t' '{print $2}')
  echo "snapshot id=$SNAP_ID status=${STATUS:-unknown} elapsed=${SECONDS}s"
  case "${STATUS}" in
    complete|active|available) break ;;
  esac
  sleep 30
done
FOUND=$(find_snapshot "$SNAP_ID" || true)
STATUS=$(echo "$FOUND" | awk -F'\t' '{print $2}')
if [[ "$STATUS" != "complete" && "$STATUS" != "active" && "$STATUS" != "available" ]]; then
  echo "snapshot not complete after wait (status=${STATUS:-none}); refusing delete to avoid data loss" >&2
  exit 1
fi

echo "single snapshot ready id=$SNAP_ID — deleting instance $INSTANCE_ID"
vultr-cli instance delete "$INSTANCE_ID"
date -u +%Y-%m-%dT%H:%M:%SZ >"$DONE_STAMP"
echo "snapshot=$SNAP_ID" >>"$DONE_STAMP"
echo "==== $(date -u +%Y-%m-%dT%H:%M:%SZ) done snapshot=$SNAP_ID deleted=$INSTANCE_ID ===="
exit 0
