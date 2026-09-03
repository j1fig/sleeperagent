# Roadmap

Each phase is independently useful and the previous phase stays working as the
fallback.

## Phase 0 — today: script + launcher + Pushover

Goal: a working call path within an hour, no code beyond shell.

- [x] `scripts/call.sh`: one POST to Pushover at emergency priority, saves the receipt.
- [x] `scripts/status.sh`: has the last call been acknowledged?
- [x] `scripts/cancel.sh`: stop retrying the last call.
- [x] `desktop/CALL.desktop.example`: a giant icon on the child's desktop.
- [x] `docs/kiosk-setup.md`: keyboard shortcut, no-suspend, no-lock, network check.
- [ ] Parent phone: Pushover installed, licensed, device named, Critical Alerts enabled for emergency priority, tested while awake, then tested while asleep.
- [ ] Daytime rehearsal of the whole flow with the child, several times.

Exit criterion: three consecutive nights in which every press produced an
acknowledged alert.

## Phase 1 — kiosk app with feedback

Goal: the child sees "seen, coming"; the system survives crashes and reboots.

- [ ] `sleeperagent` Python package per [architecture.md](architecture.md).
- [ ] Pure state machine with tests (fake clock, fake client).
- [ ] Tkinter full-screen UI: IDLE / SENDING / WAITING_ACK / ACKNOWLEDGED / FAILED, practice banner, night dimming.
- [ ] Receipt polling, idempotent press, deliberate cancel, expiry handling.
- [ ] Escalation ladder: louder re-send, optional voice-call hook.
- [ ] JSONL event log and `stats` subcommand.
- [ ] `systemd --user` unit with `Restart=always`; `install.sh`; zipapp build.
- [ ] `--dry-run` end-to-end mode.

Exit criterion: the kiosk has run for a week without manual restarts, and the
child uses the screen feedback (stays in bed after pressing).

## Phase 2 — physical button

Goal: no laptop screen needed to make the call.

- 2a. **USB single-key button** plugged into the laptop, bound to the call
  action (desktop shortcut, or an `evdev` listener in the kiosk service if the
  desktop environment cannot bind it). Cheap, immediate.
- 2b. **Standalone ESP32** (MicroPython): one big arcade button, one RGB LED,
  Wi-Fi, posts to Pushover directly and polls the receipt to turn the LED green
  on acknowledgement. Battery or USB powered. Removes the laptop from the
  critical path. Firmware lives in `firmware/` in this repo.

Exit criterion: the laptop can be closed and the button still works.

## Phase 3 — move the stimulus onto the parent's body

Goal: the other sleeper hears nothing.

- Test tier 1: phone on the mattress edge, lowest sound that reliably wakes the
  parent. Measure over several nights using the event log's time-to-ack.
- Test tier 2: smartwatch mirroring with strongest haptic setting; or a
  vibrating pager receiver.
- Tier 3: escalating haptic/electrical wrist wearable triggered by the same
  call (via its webhook/API, or via a small relay on the ESP32 driving a
  pager transmitter). Phone sound becomes the escalation rung, not the first
  rung.

Exit criterion: first rung is silent to the room, and time-to-ack stays under
the Phase 1 baseline.

## Phase 4 — fading tools

Goal: the button is used less over time, without ever being taken away.

- `stats`: calls per night, time-to-ack, cancels, practice runs; simple
  week-over-week view.
- Optional, skippable "try first" screen: a short countdown with the child's
  own calming steps listed, one key skips straight to the call. Never blocks.
- Practice mode scheduling: a gentle daytime reminder to rehearse.
- Configurable per-night "green / yellow / red" wording on the idle screen so
  the household's own rules are visible where the child needs them.

## Explicitly out of scope

- Any audio/video monitoring.
- Any lock-out, cooldown that blocks a real call, or punitive mechanic.
- Multi-household sync, accounts, cloud dashboards.
