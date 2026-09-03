#!/usr/bin/env bash
# Shared helpers for the Phase 0 scripts. Sourced, not executed.
set -euo pipefail

CONFIG_FILE="${SLEEPERAGENT_CONFIG:-$HOME/.config/sleeperagent/config}"
STATE_DIR="${SLEEPERAGENT_STATE:-$HOME/.local/state/sleeperagent}"
RECEIPT_FILE="$STATE_DIR/last-receipt"
LOG_FILE="$STATE_DIR/events.jsonl"
API="${SLEEPERAGENT_API:-https://api.pushover.net/1}"

load_config() {
  if [[ ! -r "$CONFIG_FILE" ]]; then
    echo "sleeperagent: config not found at $CONFIG_FILE (copy config.example there)" >&2
    exit 2
  fi
  # Parse KEY=VALUE lines ourselves rather than sourcing the file, so values
  # may contain spaces without quoting and the file can never execute code.
  local line key value
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]] || continue
    key="${BASH_REMATCH[1]}"; value="${BASH_REMATCH[2]}"
    value="${value#"${value%%[![:space:]]*}"}"; value="${value%"${value##*[![:space:]]}"}"
    if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then value="${BASH_REMATCH[1]}"; fi
    printf -v "$key" '%s' "$value"; export "$key"
  done < "$CONFIG_FILE"
  : "${PUSHOVER_TOKEN:?PUSHOVER_TOKEN missing in $CONFIG_FILE}"
  : "${PUSHOVER_USER:?PUSHOVER_USER missing in $CONFIG_FILE}"
  PUSHOVER_DEVICE="${PUSHOVER_DEVICE:-}"
  TITLE="${TITLE:-I need you}"
  MESSAGE="${MESSAGE:-Please come to my room.}"
  SOUND="${SOUND:-persistent}"
  RETRY_S="${RETRY_S:-30}"
  EXPIRE_S="${EXPIRE_S:-3600}"
  mkdir -p "$STATE_DIR"
}

log_event() {
  # log_event <event> [extra json fields without braces]
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local extra="${2:-}"
  if [[ -n "$extra" ]]; then
    printf '{"t":"%s","event":"%s",%s}\n' "$ts" "$1" "$extra" >> "$LOG_FILE"
  else
    printf '{"t":"%s","event":"%s"}\n' "$ts" "$1" >> "$LOG_FILE"
  fi
}

# Extract a top-level string/number value from a flat JSON object.
# Uses python3 when present (every desktop Linux), else a whitespace-tolerant sed.
json_get() {
  # json_get <key> <json>
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$2" | python3 -c 'import json,sys
try:
    v=json.load(sys.stdin).get(sys.argv[1],"")
except Exception:
    v=""
print("" if v is None else v)' "$1"
  else
    printf '%s' "$2" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^,\"}]*\)\"\{0,1\}.*/\1/p" | head -n1
  fi
}
