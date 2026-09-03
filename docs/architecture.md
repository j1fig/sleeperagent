# Architecture

## Components

```
 child's room                                   cloud                 parent's bedside
┌──────────────────────────┐                ┌────────────┐           ┌──────────────────┐
│ Linux laptop (kiosk)     │  POST message  │            │  APNs     │ iPhone           │
│  ┌─────────────────────┐ │ ─────────────► │  Pushover  │ ────────► │  Pushover app    │
│  │ sleeperagent app    │ │                │            │ retry     │  Critical Alert  │
│  │  - big button       │ │  GET receipt   │  owns:     │ every 30s │  [Acknowledge]   │
│  │  - state machine    │ │ ◄────────────► │  retry     │ ◄──────── │                  │
│  │  - receipt poller   │ │                │  ack state │  ack      │  (Phase 3: relay │
│  │  - escalation       │ │  POST cancel   │  expiry    │           │   to wearable)   │
│  │  - event log        │ │ ─────────────► │            │           └──────────────────┘
│  └─────────────────────┘ │                └────────────┘
│  (Phase 2a) USB button ──┘
│  (Phase 2b) ESP32 button ─────────────────────► same API, no laptop
└──────────────────────────┘
```

Nothing of ours runs outside the child's room. Pushover holds the retry loop
and the acknowledgement state; the kiosk only asks "acknowledged yet?".

## Happy path

```
child      kiosk                      Pushover                 phone / parent
 │ press    │                            │                          │
 ├─────────►│ log pressed                │                          │
 │          │ POST /1/messages.json      │                          │
 │          │ priority=2 retry=30        │                          │
 │          │ expire=3600 device=<phone> │                          │
 │          ├───────────────────────────►│ receipt=abc…             │
 │ "Sent.   │◄───────────────────────────┤                          │
 │  Stay in │ log sent                   ├────── critical alert ───►│ (sleeping)
 │  bed."   │ every 5 s: GET receipt     ├────── again, 30 s ──────►│ (sleeping)
 │          ├───────────────────────────►│────── again, 30 s ──────►│ wakes, taps Acknowledge
 │          │                            │◄─────────────────────────┤
 │ "Seen!   │◄── acknowledged=1 ─────────┤                          │
 │ Coming." │ log acked                  │                          │ walks to child's room
 │          │                            │                          │ presses any key / "I'm here"
 │ idle     │ log reset                  │                          │
```

Time from press to first alert on the phone is typically 1–3 seconds. The
retry cadence (30 s minimum) is what carries a deep sleeper through.

## Kiosk state machine (Phase 1)

```
                 press                 200 OK + receipt
      IDLE ───────────────► SENDING ────────────────────► WAITING_ACK
       ▲                      │  network/API error            │  │
       │                      ▼                               │  │ receipt.acknowledged=1
       │                  RETRY_SEND (local backoff,          │  ▼
       │                   1,2,4,8… s, up to N tries)         │ ACKNOWLEDGED
       │                      │ gave up                       │  │
       │                      ▼                               │  │ any key / timer
       │                    FAILED  (shows configured         │  ▼
       │                            fallback instruction)     │ IDLE
       │                      │ press again → SENDING         │
       │                                                      │ unacked for escalate_after_s
       │                                                      ▼
       │                                                  ESCALATED (re-send, louder sound;
       │                                                   optional voice call) → WAITING_ACK
       │  child presses "I'm OK now" (long-press / second button)
       └────────────────────────────────── CANCELLED (POST receipt cancel) ──► IDLE
```

Rules:

- **Idempotent press.** While a call is open (SENDING/WAITING_ACK/ESCALATED),
  another press does not create a second emergency message. The screen just
  re-confirms "Sent, stay in bed".
- **Cancel is deliberate.** "I'm OK now" is a long-press or a smaller second
  button so it cannot be hit by accident. Cancelling calls the Pushover
  receipt cancel endpoint so the phone stops retrying.
- **Arrival confirmation (optional).** If `arrival_confirm=1`, ACKNOWLEDGED
  waits for a keypress on the kiosk (the parent has physically arrived). If
  none arrives within `arrival_timeout_s`, the kiosk re-sends: acknowledging
  from bed and falling back asleep is a real failure mode.
- **Practice mode.** With `--practice` or the practice toggle, the same flow
  runs with `priority=0` and a `[PRACTICE]` title prefix. The screen is
  identical apart from a banner, so daytime rehearsal exercises the real
  procedure without emergency alerts.
- **Expiry.** `expire` is passed to Pushover (default 3600 s, hard max 10800 s)
  so a call never retries forever if the kiosk dies mid-call.

## Screens

All screens: dark background, dim by default, high-contrast text, nothing else
on screen. Brightness reduced further inside configured night hours.

| State | Screen |
|-------|--------|
| IDLE | One enormous button: `CALL <PARENT_NAME>`. Small hint at the bottom: "or press the big key". |
| SENDING / RETRY_SEND | "Sending…" |
| WAITING_ACK | "Sent. <PARENT_NAME>'s phone is ringing. Stay in bed." with a gentle animation. |
| ACKNOWLEDGED | Green. "<PARENT_NAME> saw it. Coming now." |
| ESCALATED | Same as WAITING_ACK; internal only. |
| FAILED | Amber. "Couldn't reach the phone." followed by the configured `fallback_text` (e.g. what the child should do instead). Pressing again retries. |
| PRACTICE banner | Thin strip: "PRACTICE" on any of the above. |

## Modules (Phase 1)

```
sleeperagent/
  __main__.py      # CLI: run (kiosk), call, status, cancel, --practice, --dry-run
  config.py        # load KEY=VALUE config, validate, defaults
  pushover.py      # send(), receipt(), cancel(); urllib only; typed errors
  state.py         # pure state machine; no I/O; takes a clock and a client
  escalation.py    # ladder: list of (after_s, action); actions call pushover or a telephony hook
  ui.py            # Tkinter views bound to state; key bindings; night dimming
  log.py           # JSONL event writer
scripts/           # Phase 0 shell scripts (kept working forever as the fallback)
desktop/           # .desktop and systemd unit templates
tests/             # pytest; fake clock, fake client
```

`state.py` is the only part that needs careful testing and it has no I/O, so
it is testable in milliseconds. `ui.py` is a thin renderer of state.

## Configuration

`~/.config/sleeperagent/config`, `KEY=VALUE` per line, `#` comments, mode 0600.

| Key | Default | Meaning |
|-----|---------|---------|
| `PUSHOVER_TOKEN` | required | Application token. Create a dedicated application for this. |
| `PUSHOVER_USER` | required | User (or group) key. |
| `PUSHOVER_DEVICE` | empty (all devices) | Device name of the parent's phone. Set it, so a tablet in the living room does not start screaming. |
| `PARENT_NAME` | `Parent` | Shown on the button and screens. |
| `TITLE` | `I need you` | Notification title. |
| `MESSAGE` | `Please come to my room.` | Notification body. |
| `SOUND` | `persistent` | Pushover sound for the first send. |
| `ESCALATE_SOUND` | `siren` | Sound for the escalation re-send. |
| `RETRY_S` | `30` | Pushover retry interval. Minimum 30. |
| `EXPIRE_S` | `3600` | Pushover expiry. Maximum 10800. |
| `POLL_S` | `5` | Receipt polling interval while a call is open. |
| `ESCALATE_AFTER_S` | `180` | Unacknowledged for this long → escalation rung 1. |
| `VOICE_CALL_HOOK` | empty | Optional command to run as escalation rung 2 (e.g. a script hitting a telephony API). |
| `ARRIVAL_CONFIRM` | `0` | 1 = require a keypress on the kiosk after ack, else re-send after `ARRIVAL_TIMEOUT_S`. |
| `ARRIVAL_TIMEOUT_S` | `600` | See above. |
| `RESET_AFTER_S` | `900` | Return to IDLE this long after ack if nobody pressed a key. |
| `FALLBACK_TEXT` | `Go and find a grown-up.` | Shown on FAILED. Household decides the wording. |
| `NIGHT_FROM` / `NIGHT_TO` | `21:00` / `07:00` | Extra-dim window. |
| `CALL_KEY` | `F12` | Key that triggers a call when the kiosk has focus. |

## Event log

`~/.local/state/sleeperagent/events.jsonl`, one JSON object per line:

```json
{"t":"2026-01-01T03:12:40+00:00","event":"pressed","practice":false}
{"t":"2026-01-01T03:12:41+00:00","event":"sent","receipt":"r…","priority":2}
{"t":"2026-01-01T03:14:02+00:00","event":"acked","ack_after_s":81}
{"t":"2026-01-01T03:20:11+00:00","event":"reset","by":"keypress"}
```

Events: `pressed`, `sent`, `send_failed`, `acked`, `escalated`, `cancelled`,
`expired`, `arrival_confirmed`, `arrival_timeout`, `reset`. A `stats`
subcommand summarises calls per night and median time-to-ack. This is the data
that lets the household see the button being used less over time.

## Failure modes

| Failure | Detection | Behaviour |
|---------|-----------|-----------|
| Laptop has no network | POST fails | Local backoff retries, then FAILED screen with fallback text. Logged. |
| Pushover API down / 4xx | Non-200 | Same as above; 4xx errors (bad token, invalid device) are shown verbosely in `status` and logged, but the child screen stays simple. |
| Phone off / no signal | Receipt never acknowledges | Pushover keeps retrying for `EXPIRE_S`; kiosk escalates after `ESCALATE_AFTER_S`; optional voice-call rung. Child sees "still ringing", not "seen". |
| Parent acks and falls back asleep | No kiosk keypress after ack | With `ARRIVAL_CONFIRM=1`, re-send after `ARRIVAL_TIMEOUT_S`. |
| Laptop suspended / locked | Not detectable at 3 a.m. | Prevented by configuration (see kiosk-setup.md): no suspend, no lock, auto-login, kiosk service `Restart=always`. |
| Kiosk crashed | systemd | `Restart=always`, 2 s delay. State is re-derived: an open receipt id is persisted to `~/.local/state/sleeperagent/last-receipt` and re-polled on start. |
| Double press | State machine | Ignored while a call is open. |
| Accidental cancel | Long-press only | And the cancel is logged; the parent sees it in `stats`. |
| Token leaked from the laptop | n/a | Dedicated Pushover application; revoke and rotate. Messages contain no personal data. |
| Practice message at night by mistake | Priority 0 | Harmless; it is a normal notification. |

## Security and privacy

- Outbound HTTPS to `api.pushover.net` only. Nothing listens on the laptop.
- Secrets in a 0600 file in the child's home. Accept that the child's account
  can read them; scope the token to this single purpose.
- Message contents are fixed strings from config. No names are required.
- The event log is local. Nothing is uploaded anywhere.
