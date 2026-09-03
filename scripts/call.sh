#!/usr/bin/env bash
# Page the parent. Emergency priority: the phone keeps alerting every RETRY_S
# seconds until the parent taps Acknowledge, or EXPIRE_S seconds pass.
#
#   call.sh              real call (priority 2)
#   call.sh --practice   rehearsal (priority 0, "[PRACTICE]" prefix)
#
# If a call is already open and unacknowledged, this does NOT send a second
# emergency message; it just reports that the phone is still ringing.
# shellcheck disable=SC1091
source "$(dirname "$(readlink -f "$0")")/_common.sh"
load_config

practice=0
[[ "${1:-}" == "--practice" ]] && practice=1

if (( ! practice )) && [[ -s "$RECEIPT_FILE" ]]; then
  receipt="$(cat "$RECEIPT_FILE")"
  resp="$(curl -fsS --max-time 10 "$API/receipts/$receipt.json?token=$PUSHOVER_TOKEN" 2>/dev/null || true)"
  if [[ -n "$resp" ]] && [[ "$(json_get acknowledged "$resp")" == "0" ]] && [[ "$(json_get expired "$resp")" == "0" ]]; then
    log_event pressed '"practice":false,"duplicate":true'
    echo "Already calling. The phone is still ringing. Stay in bed."
    exit 0
  fi
fi

log_event pressed "\"practice\":$([[ $practice == 1 ]] && echo true || echo false)"

args=(
  --form-string "token=$PUSHOVER_TOKEN"
  --form-string "user=$PUSHOVER_USER"
  --form-string "message=$MESSAGE"
  --form-string "sound=$SOUND"
)
[[ -n "$PUSHOVER_DEVICE" ]] && args+=(--form-string "device=$PUSHOVER_DEVICE")

if (( practice )); then
  args+=(--form-string "title=[PRACTICE] $TITLE" --form-string "priority=0")
else
  args+=(
    --form-string "title=$TITLE"
    --form-string "priority=2"
    --form-string "retry=$RETRY_S"
    --form-string "expire=$EXPIRE_S"
  )
fi

# Local retry with backoff in case the network is momentarily down.
resp=""
for delay in ${SLEEPERAGENT_RETRY_DELAYS:-1 2 4 8 16}; do
  if resp="$(curl -sS --max-time 15 "${args[@]}" "$API/messages.json")"; then
    [[ "$(json_get status "$resp")" == "1" ]] && break
  fi
  echo "sleeperagent: send failed, retrying in ${delay}s ($resp)" >&2
  sleep "$delay"
  resp=""
done

if [[ -z "$resp" ]] || [[ "$(json_get status "$resp")" != "1" ]]; then
  log_event send_failed
  echo "Couldn't reach the phone. ${FALLBACK_TEXT:-Go and find a grown-up.}"
  exit 1
fi

if (( practice )); then
  log_event sent '"practice":true,"priority":0'
  echo "Practice message sent."
else
  receipt="$(json_get receipt "$resp")"
  printf '%s' "$receipt" > "$RECEIPT_FILE"
  log_event sent "\"practice\":false,\"priority\":2,\"receipt\":\"$receipt\""
  echo "Sent. The phone is ringing. Stay in bed."
fi
