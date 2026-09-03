# sleeperagent

A silent night-time call button for a child's room.

One press on the child's device pages a parent's phone, keeps paging until the
parent acknowledges, and shows the child that help is on the way. The child
stays in their own bed. Nobody else in the house is woken.

## Why

A child who wakes at night usually walks to the parents' room. That wakes
everyone in it, and it teaches the child that "getting help" means "leaving my
room". sleeperagent replaces that chain with a different one:

```
before:  wake → scared → walk to parents' room → wake everyone → reassurance
after:   wake → scared → press the button → wait in own bed → one parent arrives
```

The button is a transitional tool, not a permanent accommodation. Because every
call is logged and the flow is rehearsable in daylight, it can be faded over
time (fewer calls, longer self-settling first) without ever taking away the
child's ability to reach a parent.

## Design goals

1. **One press, no reading, no thinking.** Usable half-asleep by a young child.
2. **Wakes one specific parent.** The signal goes to that parent's body/phone,
   not into the room.
3. **Keeps trying until acknowledged.** A single missed notification is a
   failure of the whole system.
4. **Tells the child what is happening.** "Sent" → "Seen, coming" on screen, so
   waiting in bed is bearable.
5. **Works on a locked-down device.** The child's Linux laptop has parental
   controls that block web browsers, so nothing here depends on a browser.
6. **Boring and robust.** No server to run, no database, minimal dependencies,
   survives reboots and crashes unattended.
7. **Fadeable.** Practice mode and a local call log support gradually reducing
   dependence on the button.

## Non-goals

- Not a baby monitor. No audio, no video, no listening.
- Not a punishment or lock-out mechanism. Calling for help is always allowed.
- Not a hosted product. Single household, single parent phone, local config.

## Status

Planning and Phase 0. See [docs/roadmap.md](docs/roadmap.md).

| Phase | What                                                      | State    |
|-------|-----------------------------------------------------------|----------|
| 0     | Shell script + desktop launcher/hotkey → Pushover         | usable   |
| 1     | Full-screen kiosk app with "seen, coming" feedback        | specified|
| 2     | Physical bedside button (USB key, then standalone ESP32)  | planned  |
| 3     | Parent-side wearable receiver and escalation ladder       | planned  |
| 4     | Fading tools: practice mode, call log, stats              | planned  |

## Quick start (Phase 0, works today)

Prerequisites: a [Pushover](https://pushover.net) account, the Pushover app on
the parent's phone, and an application token created at pushover.net/apps.

```sh
# on the child's Linux machine
git clone https://github.com/j1fig/sleeperagent
cd sleeperagent
mkdir -p ~/.config/sleeperagent
cp config.example ~/.config/sleeperagent/config
chmod 600 ~/.config/sleeperagent/config
$EDITOR ~/.config/sleeperagent/config   # fill in token, user key, device name
./scripts/call.sh --practice             # normal-priority test message
./scripts/call.sh                        # real emergency-priority call
```

Then wire the script to something the child can press without a terminal:
a desktop icon (`desktop/CALL.desktop.example`) or a keyboard shortcut. Full
instructions, including power and lock-screen settings so the laptop is still
usable at 3 a.m., are in [docs/kiosk-setup.md](docs/kiosk-setup.md).

## Documents

- [docs/tech-stack.md](docs/tech-stack.md) — the stack, and what was rejected and why
- [docs/architecture.md](docs/architecture.md) — components, flows, state machine, failure modes
- [docs/roadmap.md](docs/roadmap.md) — phases from "today" to "no phone sound at all"
- [docs/kiosk-setup.md](docs/kiosk-setup.md) — preparing a parental-controlled Linux laptop
- [docs/adr/](docs/adr/) — architecture decision records

## Privacy

This is a public repository. It contains no personal information, and it must
stay that way: no names, no household details, no logs. API tokens live only in
`~/.config/sleeperagent/config` (gitignored). Call logs stay on the child's
device.

## License

MIT
