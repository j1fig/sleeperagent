#!/usr/bin/env bash
# sleeperagent one-line installer for the child's Linux laptop.
#
#   curl -fsSL https://raw.githubusercontent.com/j1fig/sleeperagent/main/install.sh | bash
#
# Run it from the child's own desktop session (the account that will press the
# button). It asks for the Pushover keys, or reads them from the environment:
#
#   PUSHOVER_TOKEN=... PUSHOVER_USER=... PUSHOVER_DEVICE=... PARENT_NAME=... \
#     curl -fsSL .../install.sh | bash
#
# What it does:
#   1. downloads scripts/ from this repository into ~/.local/bin
#   2. writes ~/.config/sleeperagent/config (mode 600) after validating the keys
#   3. puts a big CALL icon on the desktop and binds a hotkey (GNOME: F12)
#   4. stops the laptop suspending or locking (GNOME gsettings)
#   5. root-only extras via sudo when available: ignore the lid switch, mask
#      suspend, enable auto-login for this account
#   6. mutes the speakers and sends a practice message to the phone
#
# Flags:  --reconfigure   ask for the keys again even if a config exists
#         --no-system     skip the sudo steps
#         --uninstall     remove icon, hotkey, scripts (keeps config and log)
# Env:    SLEEPERAGENT_REF   git ref to install from (default: main)
#         SLEEPERAGENT_KEY   hotkey (default: F12)
set -euo pipefail

REPO="j1fig/sleeperagent"
REF="${SLEEPERAGENT_REF:-main}"
KEY="${SLEEPERAGENT_KEY:-F12}"
API="${SLEEPERAGENT_API:-https://api.pushover.net/1}"
BIN="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/sleeperagent"
CONFIG="$CONFIG_DIR/config"
STATE_DIR="$HOME/.local/state/sleeperagent"
DESKTOP_DIR="$(command -v xdg-user-dir >/dev/null 2>&1 && xdg-user-dir DESKTOP || echo "$HOME/Desktop")"
ICON="$DESKTOP_DIR/CALL.desktop"
KB_SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
KB_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/sleeperagent/"

RECONFIGURE=0; NO_SYSTEM=0; UNINSTALL=0
USER="${USER:-$(id -un)}"
for a in "$@"; do
  case "$a" in
    --reconfigure) RECONFIGURE=1 ;;
    --no-system)   NO_SYSTEM=1 ;;
    --uninstall)   UNINSTALL=1 ;;
    *) echo "unknown flag: $a" >&2; exit 2 ;;
  esac
done

TODO=()
say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m ! \033[0m %s\n' "$*"; }
todo() { TODO+=("$*"); warn "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# Read from the terminal even when stdin is the curl pipe.
tty_ok() { { : < /dev/tty; } 2>/dev/null; }
ask() {
  # ask <var> <prompt> [default]   -- a default of "-" means "optional, blank allowed"
  local var="$1" prompt="$2" def="${3:-}" val=""
  if [[ -n "${!var:-}" ]]; then return 0; fi
  if ! tty_ok; then
    [[ -z "$def" ]] && die "no terminal to ask for $var; set it in the environment and rerun"
    [[ "$def" == "-" ]] && def=""
    printf -v "$var" '%s' "$def"; return 0
  fi
  if [[ "$def" == "-" ]]; then
    read -r -p "$prompt (blank = all devices): " val < /dev/tty || die "input aborted"
  elif [[ -n "$def" ]]; then
    read -r -p "$prompt [$def]: " val < /dev/tty || die "input aborted"
    val="${val:-$def}"
  else
    while [[ -z "$val" ]]; do read -r -p "$prompt: " val < /dev/tty || die "input aborted"; done
  fi
  printf -v "$var" '%s' "$val"
}

have() { command -v "$1" >/dev/null 2>&1; }
is_gnome() { have gsettings && [[ "${XDG_CURRENT_DESKTOP:-}${DESKTOP_SESSION:-}" == *[Gg][Nn][Oo][Mm][Ee]* || -n "${GNOME_DESKTOP_SESSION_ID:-}" ]]; }

# --- uninstall ---------------------------------------------------------------
if (( UNINSTALL )); then
  say "Removing sleeperagent (config and log are kept)"
  rm -f "$ICON" "$BIN"/call.sh "$BIN"/status.sh "$BIN"/cancel.sh "$BIN"/_common.sh
  if have gsettings && have python3; then
    cur="$(gsettings get "$KB_SCHEMA" custom-keybindings 2>/dev/null || echo "@as []")"
    new="$(python3 - "$cur" "$KB_PATH" <<'PY'
import ast,sys
cur=sys.argv[1].replace("@as ","",1); lst=ast.literal_eval(cur) if cur.strip() else []
lst=[p for p in lst if p!=sys.argv[2]]; print(repr(lst) if lst else "@as []")
PY
)"
    gsettings set "$KB_SCHEMA" custom-keybindings "$new" 2>/dev/null || true
    gsettings reset-recursively "$KB_SCHEMA.custom-keybinding:$KB_PATH" 2>/dev/null || true
  fi
  say "Done. Power, lock-screen and auto-login settings were left as they are."
  exit 0
fi

# --- 0. prerequisites ------------------------------------------------------------
have curl || die "curl is required"
have tar  || die "tar is required"
have python3 || warn "python3 not found; the scripts fall back to a simpler JSON parser"

# --- 1. fetch the scripts --------------------------------------------------------
SRC=""
if [[ -f "${BASH_SOURCE[0]:-/nonexistent}" ]] && [[ -f "$(dirname "${BASH_SOURCE[0]}")/scripts/call.sh" ]]; then
  SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  say "Installing from local checkout $SRC"
else
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  say "Downloading sleeperagent ($REF)"
  curl -fsSL "https://github.com/$REPO/archive/$REF.tar.gz" | tar -xz -C "$TMP" --strip-components=1 \
    || die "could not download https://github.com/$REPO/archive/$REF.tar.gz"
  SRC="$TMP"
fi
mkdir -p "$BIN" "$CONFIG_DIR" "$STATE_DIR"
install -m 755 "$SRC"/scripts/call.sh "$SRC"/scripts/status.sh "$SRC"/scripts/cancel.sh "$BIN"/
install -m 644 "$SRC"/scripts/_common.sh "$BIN"/
say "Scripts installed to $BIN"
case ":$PATH:" in *":$BIN:"*) ;; *) warn "$BIN is not on PATH; use full paths or log out and in again" ;; esac

# --- 2. configuration ------------------------------------------------------------
if [[ -f "$CONFIG" ]] && (( ! RECONFIGURE )); then
  say "Keeping existing config $CONFIG (use --reconfigure to change it)"
else
  echo
  echo "Pushover setup. Create a dedicated application at https://pushover.net/apps"
  echo "and find your user key at https://pushover.net. The device name is shown in"
  echo "the Pushover app on the parent's phone."
  ask PUSHOVER_TOKEN "Application token"
  ask PUSHOVER_USER  "User key"
  ask PUSHOVER_DEVICE "Parent phone device name" "-"
  ask PARENT_NAME "Parent name shown on the button" "Parent"
  say "Validating keys with Pushover"
  vargs=(--form-string "token=$PUSHOVER_TOKEN" --form-string "user=$PUSHOVER_USER")
  [[ -n "$PUSHOVER_DEVICE" ]] && vargs+=(--form-string "device=$PUSHOVER_DEVICE")
  vresp="$(curl -sS --max-time 15 "${vargs[@]}" "$API/users/validate.json" || true)"
  if [[ "$vresp" != *'"status":1'* && "$vresp" != *'"status": 1'* ]]; then
    die "Pushover rejected the keys or device: ${vresp:-no response}. Nothing was written; rerun to try again."
  fi
  sed -e "s|^PUSHOVER_TOKEN=.*|PUSHOVER_TOKEN=$PUSHOVER_TOKEN|" \
      -e "s|^PUSHOVER_USER=.*|PUSHOVER_USER=$PUSHOVER_USER|" \
      -e "s|^PUSHOVER_DEVICE=.*|PUSHOVER_DEVICE=$PUSHOVER_DEVICE|" \
      -e "s|^PARENT_NAME=.*|PARENT_NAME=$PARENT_NAME|" \
      "$SRC/config.example" > "$CONFIG.tmp"
  chmod 600 "$CONFIG.tmp"; mv "$CONFIG.tmp" "$CONFIG"
  say "Config written to $CONFIG"
fi

# --- 3. desktop icon and hotkey ------------------------------------------------
mkdir -p "$DESKTOP_DIR"
sed "s|__HOME__|$HOME|g" "$SRC/desktop/CALL.desktop.example" > "$ICON"
chmod +x "$ICON"
if have gio; then gio set "$ICON" metadata::trusted true 2>/dev/null || true; fi
say "Desktop icon: $ICON"

if is_gnome && have python3; then
  cur="$(gsettings get "$KB_SCHEMA" custom-keybindings 2>/dev/null || echo "@as []")"
  new="$(python3 - "$cur" "$KB_PATH" <<'PY'
import ast,sys
cur=sys.argv[1].replace("@as ","",1); lst=ast.literal_eval(cur) if cur.strip() else []
if sys.argv[2] not in lst: lst.append(sys.argv[2])
print(repr(lst))
PY
)"
  if gsettings set "$KB_SCHEMA" custom-keybindings "$new" \
     && gsettings set "$KB_SCHEMA.custom-keybinding:$KB_PATH" name 'CALL' \
     && gsettings set "$KB_SCHEMA.custom-keybinding:$KB_PATH" command "$BIN/call.sh" \
     && gsettings set "$KB_SCHEMA.custom-keybinding:$KB_PATH" binding "$KEY"; then
    say "Hotkey $KEY bound to $BIN/call.sh (GNOME)"
  else
    todo "Could not bind $KEY via gsettings. Bind a hotkey manually to $BIN/call.sh (docs/kiosk-setup.md section 3)."
  fi
else
  todo "Bind a hotkey manually to $BIN/call.sh (desktop is not GNOME or gsettings is missing). See docs/kiosk-setup.md."
fi

# --- 4. never suspend, never lock (user level) ----------------------------------
if have gsettings; then
  gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
  gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' 2>/dev/null || true
  gsettings set org.gnome.settings-daemon.plugins.power power-button-action 'nothing' 2>/dev/null || true
  gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
  gsettings set org.gnome.desktop.screensaver ubuntu-lock-on-suspend false 2>/dev/null || true
  gsettings set org.gnome.desktop.session idle-delay 300 2>/dev/null || true
  say "Power: no suspend, no lock screen, screen blanks after 5 min (a keypress wakes it)"
else
  todo "Disable automatic suspend and the lock screen in your desktop's settings."
fi

# --- 5. root-only extras -------------------------------------------------------------
ROOT_SCRIPT="$(cat <<EOS
set -e
mkdir -p /etc/systemd/logind.conf.d
printf '[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\nHandleLidSwitchDocked=ignore\n' > /etc/systemd/logind.conf.d/sleeperagent.conf
systemctl kill -s HUP systemd-logind 2>/dev/null || true
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >/dev/null 2>&1 || true
for f in /etc/gdm3/custom.conf /etc/gdm/custom.conf; do
  [ -f "\$f" ] || continue
  python3 - "\$f" "$USER" <<'PY'
import re,sys
p,user=sys.argv[1],sys.argv[2]; s=open(p).read()
if '[daemon]' not in s: s+='\n[daemon]\n'
def setkey(s,k,v):
    if re.search(r'(?m)^\s*#?\s*'+k+r'\s*=',s): return re.sub(r'(?m)^\s*#?\s*'+k+r'\s*=.*$',f'{k}={v}',s,count=1)
    return s.replace('[daemon]',f'[daemon]\n{k}={v}',1)
s=setkey(s,'AutomaticLoginEnable','True'); s=setkey(s,'AutomaticLogin',user)
open(p,'w').write(s)
PY
  echo "auto-login enabled for $USER in \$f"
done
EOS
)"
if (( NO_SYSTEM )); then
  todo "Skipped root steps (--no-system): lid switch, suspend masking, auto-login."
elif have sudo && { sudo -n true 2>/dev/null || { tty_ok && sudo -v < /dev/tty 2>/dev/null; }; }; then
  say "Applying root settings (lid switch ignored, suspend masked, auto-login)"
  sudo bash -c "$ROOT_SCRIPT" || todo "Root steps failed; see docs/kiosk-setup.md section 4."
else
  todo "This account cannot sudo. From an admin account run:  curl -fsSL https://raw.githubusercontent.com/$REPO/$REF/install.sh | sudo -u $USER bash -s -- --reconfigure  (or apply docs/kiosk-setup.md section 4 by hand)"
fi

# --- 6. mute and practice --------------------------------------------------------
if have pactl; then pactl set-sink-mute @DEFAULT_SINK@ 1 2>/dev/null || true
elif have amixer; then amixer -q set Master mute 2>/dev/null || true; fi

say "Sending a practice message to the phone"
if "$BIN/call.sh" --practice; then
  say "Check the phone: a normal-priority '[PRACTICE]' notification should have arrived."
else
  todo "Practice message failed to send. Check the network and $CONFIG."
fi

# --- summary ---------------------------------------------------------------------
echo
say "Installed. Routine for the child: wake → press $KEY (or the CALL icon) → stay in bed."
echo "  real call:   $BIN/call.sh        status: $BIN/status.sh        stop: $BIN/cancel.sh"
echo "  log:         $STATE_DIR/events.jsonl"
echo
echo "On the parent's phone, still to do by hand:"
echo "  - Pushover app → Settings → enable Critical Alerts for emergency priority"
echo "  - keep the phone at the bedside; do one real call with $BIN/call.sh and tap Acknowledge"
if ((${#TODO[@]})); then
  echo; echo "Left for you to do:"; for t in "${TODO[@]}"; do echo "  - $t"; done
fi
