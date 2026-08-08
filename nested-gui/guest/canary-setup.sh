#!/usr/bin/env bash
set -euo pipefail
CANARY_DIR="${CANARY_DIR:-$HOME/dnd-canary}"
TOKEN="${DND_CANARY_TOKEN:-DNDCANARY$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d - | cut -c1-16)}"
mkdir -p "$CANARY_DIR"
echo "secret-should-never-reach-page $TOKEN" >"$CANARY_DIR/canary.txt"
echo "$TOKEN" >"${OUT_DIR:-/tmp}/canary.token"
chmod 600 "$CANARY_DIR/canary.txt"
echo "canary at $CANARY_DIR/canary.txt token=$TOKEN"
