#!/usr/bin/env bash
# Print month-to-date actual cost in USD for the Azure subscription.
#
# Writes a bare number to stdout on success. Exits 1 when the cost API is not
# readable, so callers can fall back to their own accounting instead of
# assuming zero spend. Never print anything but the number on stdout.
#
# Needs a role that can read cost: Cost Management Reader at subscription
# scope. Virtual Machine Contributor alone is not enough.
set -euo pipefail

SUB="${AZURE_SUBSCRIPTION_ID:-}"
RETRIES="${COST_QUERY_RETRIES:-4}"
API="${COST_API_VERSION:-2023-11-01}"

log() { echo "$*" >&2; }

if [[ -z "$SUB" ]]; then
  SUB=$(az account show --query id -o tsv 2>/dev/null || true)
fi
if [[ -z "$SUB" ]]; then
  SUB=$(curl -s -H Metadata:true --max-time 5 \
    "http://169.254.169.254/metadata/instance/compute/subscriptionId?api-version=2021-02-01&format=text" 2>/dev/null || true)
fi
if [[ -z "$SUB" ]]; then
  log "cost-mtd: no subscription id"
  exit 1
fi

URL="https://management.azure.com/subscriptions/${SUB}/providers/Microsoft.CostManagement/query?api-version=${API}"
BODY='{"type":"ActualCost","timeframe":"MonthToDate","dataSet":{"granularity":"None","aggregation":{"totalCost":{"name":"Cost","function":"Sum"}}}}'

# Cost Management throttles hard. Back off rather than failing the first 429.
delay=5
for attempt in $(seq 1 "$RETRIES"); do
  if out=$(az rest --method POST --url "$URL" --body "$BODY" \
      --query "properties.rows[0][0]" -o tsv 2>/dev/null); then
    if [[ -n "$out" && "$out" != "None" ]]; then
      printf '%s\n' "$out"
      exit 0
    fi
    # An empty result set means no usage recorded yet this month.
    printf '0\n'
    exit 0
  fi
  log "cost-mtd: query attempt ${attempt}/${RETRIES} failed; retrying in ${delay}s"
  sleep "$delay"
  delay=$(( delay * 2 ))
done

log "cost-mtd: cost API unreadable after ${RETRIES} attempts"
exit 1
