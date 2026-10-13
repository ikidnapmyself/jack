# jack: local dev toolkit

## Goal

One entry point for small local dev chores, grouped by theme. First theme is `port`: list and kill TCP listeners. Future themes such as `clean` drop in without touching existing code.

## Decisions

- Language: bash, shebang `#!/usr/bin/env bash`, bash 3.2 compatible because macOS ships 3.2. No associative arrays or other bash 4 features.
- CLI shape: `jack <theme> <action> [args]`.
- Extension model: drop-in `lib/<theme>.sh` files. `bin/jack` is symlinked onto PATH.
- Scope: TCP listeners only.

## Layout

```
bin/jack          dispatcher
lib/core.sh       shared helpers: colors, confirm, die, require_cmd
lib/port.sh       port theme
docs/plans/       design docs
tests/            bats tests
```

## Dispatch

`bin/jack` resolves its own real path through the symlink, sources `lib/core.sh`, then sources `lib/<theme>.sh` and calls `<theme>_<action>`.

- `jack` with no args scans `lib/*.sh` and prints each theme with its `JACK_DESC` line.
- `jack <theme>` lists actions by matching function names `^<theme>_`.
- Unknown theme or action prints a usage hint and exits 2.

## Extension contract

A theme is `lib/<theme>.sh` containing:

- `JACK_DESC="one line description"`
- functions named `<theme>_<action>`

It may use anything from `core.sh`. No other file needs editing.

## Theme: port

### `jack port list [port]`

Runs `lsof -nP -iTCP -sTCP:LISTEN`. Prints PORT, PID, USER, COMMAND and the full command line from `ps -o command= -p <pid>`. Sorted by port. With a port argument, filters to that port. Exits 1 when nothing matches.

### `jack port kill <port> [-y]`

1. Find PIDs listening on the port. None found: message, exit 1.
2. Show each PID, user and command line.
3. Prompt `Kill N process(es)? [y/N]` unless `-y`.
4. Send SIGTERM, poll up to 3 seconds, then SIGKILL anything still alive.
5. Report what died and how. Exit 1 if anything survived.

Edge cases:

- Several PIDs on one port, such as forked workers: all are killed.
- EPERM on another user's process: report it and print a hint to retry with sudo. The tool never runs sudo itself.
- Port must be an integer 1 to 65535, otherwise usage error, exit 2.

## Errors and output

- `core.sh` sets `set -u`. `die` writes to stderr and exits 1.
- `require_cmd lsof` runs at the start of the port theme.
- Colors are off when stdout isn't a TTY or `NO_COLOR` is set.
- Exit codes: 0 success, 1 runtime failure or nothing found, 2 usage error.

## Testing

bats-core via brew. Tests start a throwaway listener with `python3 -m http.server <random high port>` and assert on `port list` and `port kill -y`. One test uses a listener that traps SIGTERM to prove the SIGKILL escalation. Usage and validation errors are tested without side effects.

## Out of scope

UDP and established connections, interactive pickers, any theme besides `port`. Likely next theme: `clean`.
