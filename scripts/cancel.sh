#!/usr/bin/env bash
# Stop the retries of the last emergency call (e.g. "I'm OK now", or testing).
# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/_common.sh"
load_config

[[ -s "$RECEIPT_FILE" ]] || { echo "No call on record."; exit 2; }
receipt="$(cat "$RECEIPT_FILE")"
resp="$(curl -fsS --max-time 10 --form-string "token=$PUSHOVER_TOKEN" "$API/receipts/$receipt/cancel.json")" || { echo "Cancel failed."; exit 1; }
if [[ "$(json_get status "$resp")" == "1" ]]; then
  log_event cancelled "\"receipt\":\"$receipt\""
  rm -f "$RECEIPT_FILE"
  echo "Cancelled."
else
  echo "Cancel failed: $resp"
  exit 1
fi
