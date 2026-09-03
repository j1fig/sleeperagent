# ADR 0002: Native full-screen kiosk instead of a web UI

Status: accepted

## Context

The child's laptop runs parental controls that block web browsers. The child
must be able to trigger a call and see feedback half-asleep.

## Decision

Phase 0 uses a `.desktop` launcher and a desktop-environment keyboard
shortcut. Phase 1 is a full-screen Python + Tkinter application: one huge
button, one key binding, four states on screen.

## Consequences

- No browser, no Electron, no web toolchain.
- Tkinter needs `python3-tk` on distros that split it out; otherwise zero
  dependencies. GTK via PyGObject remains a viable swap if Tk proves lacking.
- Global hotkeys are the desktop environment's job (Wayland forbids app-level
  grabs); the kiosk binds keys only when focused, and it keeps focus by being
  the only full-screen window.
