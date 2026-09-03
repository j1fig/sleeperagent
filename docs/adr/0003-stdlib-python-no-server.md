# ADR 0003: Python standard library only on the child's device; no server of our own

Status: accepted

## Context

The laptop is locked down and unmaintained. Anything that needs `pip`, a
virtualenv, Node, or a running service elsewhere in the house will rot.

## Decision

Runtime code on the laptop uses only the Python standard library (`urllib`,
`json`, `tkinter`, `logging`) and is shipped as a single zipapp. Configuration
is a `KEY=VALUE` file shared by the shell scripts and the app. No server, API,
database, or accounts are built. Tests and packaging tools run only on the
developer machine.

## Consequences

- Installation is "copy two files, enable one unit".
- Some conveniences (rich HTTP client, TOML) are forgone; the HTTP surface is
  three endpoints, so this costs little.
- If a stronger UI or binary distribution is ever wanted, a Go/Rust build is
  the escape hatch, not a Python dependency tree.
