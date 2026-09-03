# Tech stack

This document fixes the stack for sleeperagent and records why each
alternative lost. Decisions with lasting consequences also have an ADR in
[adr/](adr/).

## The constraints that decide everything

| # | Constraint | Consequence |
|---|------------|-------------|
| C1 | The child's device is a Linux laptop with parental controls that **block web browsers**. | The child-facing UI cannot be a web page, a PWA, or an Electron app. It must be a native window or a keyboard shortcut. |
| C2 | The child's account may not be able to install packages, and nobody wants to maintain a toolchain on that machine. | The runtime on the laptop must be what ships with the distro: Python 3 standard library, `curl`, `systemd`. No `pip`, no `npm`. |
| C3 | The parent is a very deep sleeper. The other adult in the room must not be woken. | The alert must be **retried until acknowledged**, must bypass mute/Focus, and must be aimed at the parent's body (phone at the bedside now, a wearable later), never at the room. |
| C4 | The child must not be left wondering whether the button worked. | The child device needs a feedback loop: sent → seen → coming. That requires reading acknowledgement state back. |
| C5 | It has to work tonight, unattended, at 3 a.m., with nobody there to debug it. | No server of our own. Fewest moving parts. Retry/ack state owned by a service whose whole job is that. Restart on crash. Survives reboot. |
| C6 | Public repository. | Zero personal data in code, docs, defaults, or examples. Secrets only in a gitignored local config. |

## Decision summary

| Layer | Choice | Why |
|-------|--------|-----|
| Notification transport | **Pushover**, emergency priority (`priority=2`) | The only mainstream push service that natively retries a message every N seconds until the recipient explicitly acknowledges it, exposes that acknowledgement via a receipts API, supports cancelling the retry, and delivers as an iOS **Critical Alert** that bypasses mute and Focus. One HTTP POST replaces a whole retry/ack loop we would otherwise have to write and babysit. |
| Parent receiver (now) | iPhone with the Pushover app, Critical Alerts enabled for emergency priority, phone at the bedside | Available today, zero hardware. Loudness is the trade-off; see roadmap Phase 3 for moving the stimulus onto the wrist. |
| Child interface (Phase 0) | Shell script + `.desktop` launcher and/or a desktop-environment keyboard shortcut | Works without a browser, no code to maintain, done in an afternoon. |
| Child interface (Phase 1) | **Native full-screen kiosk app in Python + Tkinter** | Tkinter is in the standard library (one distro package, `python3-tk`, if the distro splits it out). Full-screen, giant button, key bindings, dark palette, no browser, no desktop-environment coupling, runs under X11 and Wayland (via XWayland). |
| Acknowledgement feedback | Poll Pushover receipts API from the kiosk every few seconds while a call is open | No inbound connectivity needed on the laptop; polling a single receipt is cheap. The `callback` URL alternative would need a public endpoint we do not want to run. |
| Escalation | A small ladder inside the kiosk app: re-send with a louder sound after N minutes unacknowledged; optional voice call via a telephony API as a last rung | Escalation belongs where the "is it acknowledged yet?" loop already lives. |
| Runtime language | **Python 3, standard library only** on the laptop (`urllib`, `json`, `tkinter`, `configparser`-style key=value parsing, `logging`) | Satisfies C2. Every desktop Linux ships Python 3. |
| Config and secrets | `~/.config/sleeperagent/config`, `KEY=VALUE` lines, mode `0600` | One format that both `sh` (Phase 0) and Python (Phase 1) read trivially. Gitignored. |
| Process supervision | `systemd --user` service, `Restart=always`, part of `graphical-session.target` | Restarts on crash, starts at login. Combined with auto-login for the child account, a reboot returns to the kiosk with no interaction. |
| Local log | Append-only JSON Lines at `~/.local/state/sleeperagent/events.jsonl` | One line per event (pressed, sent, acked, escalated, failed, reset). Supports the fading plan with real numbers. Never leaves the device. |
| Packaging | `python3 -m zipapp` → single `sleeperagent.pyz`, plus an `install.sh` that copies it and the unit file into `~/.local` | One file to copy to the laptop. No `pip`. |
| Tests | `pytest` on the developer machine only; state machine tested with a fake clock and fake Pushover client; `--dry-run` flag end to end | The laptop never needs the test tooling. |
| Physical button (Phase 2a) | A single-key USB keypad/"big button" plugged into the laptop, bound to the call action | Cheapest possible hardware; the laptop stays the hub. |
| Physical button (Phase 2b) | ESP32 running MicroPython, battery/USB powered, posts directly to Pushover over Wi-Fi | Removes the laptop from the critical path entirely. ~USD 5 of hardware. |
| Parent wearable (Phase 3) | Escalating wrist stimulus (strong haptics first, electrical-stimulus wearable if haptics prove sleep-through-able), driven by the same Pushover/webhook event | Moves the stimulus off the phone speaker and onto the parent's body, which is the only way to fully protect the other sleeper. |

## Alternatives considered

### Notification transport

| Option | Retry until ack | Bypass mute/Focus on iOS | Ack readable by sender | Self-hosting | Verdict |
|--------|-----------------|---------------------------|------------------------|--------------|---------|
| **Pushover emergency** | Yes, native, 30 s minimum interval, up to 3 h | Yes (Critical Alerts, user-enabled) | Yes, receipts API + cancel | No, one-time USD 4.99 per platform after 30-day trial | **Chosen** |
| Telegram bot | No. Would need our own loop: send, poll, resend, detect the ack button, stop | No. Normal notifications; Focus/DND suppress them; iOS coalesces repeats | Yes, via callback query | No | Rejected: we would be maintaining exactly the fragile loop Pushover already owns |
| ntfy (self-hosted or ntfy.sh) | No | Partial (no Critical Alerts entitlement on iOS) | No | Yes | Rejected for iOS reliability; good option on Android |
| Twilio / telephony voice call | Rings until answered, which is a strong stimulus | Phone calls bypass Focus only for allowed contacts | Yes (call answered) | No, per-call cost | Kept as an **optional last rung** of escalation, not the primary path; a ringing phone is the loudest thing in the room |
| Home Assistant + companion app | Yes with automations | Yes (critical notifications) | Yes | Yes, but requires running HA | Rejected: a whole platform to operate for one button. Reasonable if HA is already running in the house |
| Apple Shortcuts / iMessage | No | No | No | n/a | Rejected |

### Child interface

| Option | Works with browsers blocked | Usable half-asleep | Feedback to child | Verdict |
|--------|-----------------------------|--------------------|-------------------|---------|
| Web page / PWA | **No** (C1) | Yes | Yes | Rejected by C1 |
| Electron / Tauri app | Technically yes, but heavy and may be caught by the same app filter | Yes | Yes | Rejected: heavy, needs a toolchain |
| `.desktop` launcher icon | Yes | Yes if the icon is huge and alone on the desktop | No (fire and forget) | **Phase 0** |
| Desktop-environment keyboard shortcut | Yes | Yes, one key | No | **Phase 0**, complements the icon |
| **Native Tkinter kiosk** | Yes | Yes: full screen, one button, one key | Yes: sent / seen / coming / failed | **Phase 1** |
| GTK (PyGObject) kiosk | Yes | Yes | Yes | Close second. PyGObject is preinstalled on GNOME desktops, so it may be zero-install there, but it couples the app to the desktop stack and Tkinter is simpler to reason about |
| USB single-key button | Yes | Best: physical, no screen needed | Via kiosk screen | **Phase 2a** |
| Standalone ESP32 button | Yes, no laptop involved | Best | LED on the button (ack turns it green by polling receipts) | **Phase 2b** |

### Parent receiver

| Option | Wakes a deep sleeper | Disturbs the other sleeper | Available now | Verdict |
|--------|----------------------|----------------------------|---------------|---------|
| iPhone Critical Alert at bedside | Good; tunable by placement and sound | Some; it is still a speaker in the room | Yes | **Now** |
| iPhone + Apple Watch mirroring, prominent haptic | Unknown until tested; watch haptics are moderate | Very little | Yes if a watch is available | Test in Phase 3 |
| Vibrating caregiver pager receiver | Moderate | Very little | Off the shelf | Phase 3 option |
| Escalating haptic/electrical wrist wearable (Pavlok-style) with webhook trigger | Strongest | Essentially none | Yes, with integration work | Phase 3 target |
| Bed shaker (deaf-alarm style) | Strong | High, same mattress | Yes | Rejected |

### Language / toolkit on the laptop

| Option | Preinstalled | Verdict |
|--------|--------------|---------|
| **Python 3 + Tkinter** | Python yes; Tk usually one distro package | **Chosen** |
| Shell + curl | Yes | Phase 0 only; no state, no UI |
| Rust / Go binary | Would need to be cross-built and copied; no runtime deps | Viable later if Python proves annoying, but adds a toolchain for no user-visible gain |
| Node / Electron | No | Rejected |

## What is deliberately not built

- No server, API, database, or accounts of our own. Pushover is the only
  third party, and it is only a relay.
- No audio or video from the child's room.
- No "lock-out" mode. The button always works. Fading is done through
  practice, logging, and optional skippable prompts, never by disabling the
  call.

## Known limits to state plainly

- No consumer system can guarantee waking every sleeper every time. The design
  maximises the odds (retry until ack, critical alert, escalation) and makes
  failure visible to the child on screen instead of silent.
- Critical Alerts on iOS play at a level that ignores the ringer switch. Whether
  the Pushover app currently exposes a separate critical-alert volume must be
  checked in the app's settings on the installed version; do not rely on it.
  The real fix for loudness is Phase 3, not a volume slider.
- The Pushover application token is readable by the child's account on the
  laptop. Use a dedicated token for this app so it can be revoked without
  touching anything else.
