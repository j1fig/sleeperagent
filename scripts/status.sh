#!/usr/bin/env bash
# Has the last emergency call been acknowledged?
# Exit 0 = acknowledged, 1 = still ringing, 2 = no call / expired / error.
# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/_common.sh"
load_config

[[ -s "$RECEIPT_FILE" ]] || { echo "No call on record."; exit 2; }
receipt="$(cat "$RECEIPT_FILE")"
resp="$(curl -fsS --max-time 10 "$API/receipts/$receipt.json?token=$PUSHOVER_TOKEN")" || { echo "Could not query receipt."; exit 2; }

ack="$(json_get acknowledged "$resp")"
expired="$(json_get expired "$resp")"
if [[ "$ack" == "1" ]]; then
  at="$(json_get acknowledged_at "$resp")"
  echo "Acknowledged at $(date -d "@$at" 2>/dev/null || echo "$at")."
  exit 0
elif [[ "$expired" == "1" ]]; then
  echo "Expired without acknowledgement."
  exit 2
else
  echo "Still ringing."
  exit 1
fi
