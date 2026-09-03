# ADR 0004: Escalation and feedback logic run on the child's device

Status: accepted

## Context

Beyond Pushover's own retries, we want a louder re-send after N minutes, an
optional voice call, an on-screen "seen, coming" for the child, and optional
arrival confirmation. Something has to poll the receipt and act.

## Decision

The kiosk app on the child's device owns the "is it acknowledged yet?" loop,
the escalation ladder, arrival confirmation, and the event log. Pushover owns
retry and acknowledgement state. Nothing runs anywhere else.

## Consequences

- If the laptop dies mid-call, Pushover still retries until `expire`; only
  escalation and on-screen feedback are lost. Acceptable and visible.
- The open receipt is persisted locally so a restarted kiosk resumes polling.
- Phase 2b hardware (ESP32) must reimplement a minimal version of this loop
  (poll receipt, drive LED); the ladder stays simple on purpose so that is
  feasible.
