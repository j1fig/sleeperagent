# ADR 0001: Pushover emergency priority for the parent alert

Status: accepted

## Context

The alert must retry until a deep sleeper acknowledges it, bypass iOS
mute/Focus, expose acknowledgement state so the child's device can show
"seen", and be cancellable. It must work tonight with no server of our own.

## Decision

Use Pushover with `priority=2`, `retry=30`, `expire<=10800`, targeting a single
named device. Poll the receipts API for acknowledgement; cancel via the receipt
cancel endpoint.

## Consequences

- One HTTP POST from the child's device; Pushover owns retry and ack state.
- A one-time licence per platform for the parent's phone.
- Dependency on a third party. Mitigated by the shell-script fallback being
  trivial to point at another service, and by Phase 2b/3 hardware being
  transport-agnostic (they only need an HTTP endpoint).
- Telegram was rejected because it has no retry-until-ack and iOS suppresses
  or coalesces its notifications under Focus. ntfy was rejected for lacking
  iOS Critical Alerts. Telephony voice calls are kept as an optional last
  escalation rung.
