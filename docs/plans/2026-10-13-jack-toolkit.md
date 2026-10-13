# jack Toolkit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build `jack`, a bash dispatcher with drop-in themes, and ship the first theme: `port list` and `port kill`.

**Architecture:** `bin/jack` resolves its symlink, sources `lib/core.sh`, then sources `lib/<theme>.sh` and calls `<theme>_<action>`. Themes are single files with a `JACK_DESC` line and public `<theme>_<action>` functions. Helpers start with `_<theme>_` so they stay out of the action listing.

**Tech Stack:** bash 3.2 compatible, lsof, ps, awk, bats-core for tests.

Design: `docs/plans/2026-10-13-jack-toolkit-design.md`

Conventions: no comments in code unless they explain a non-obvious constraint. Every commit ends with the attribution trailer shown in the commands below.

---

### Task 0: Prerequisites

**Step 1: Install bats**

Run: `brew install bats-core`
Expected: `bats --version` prints `Bats 1.x`.

**Step 2: Add ignore file and commit**

```bash
cd /Users/burak/Projects/jack-all-trades
printf '.DS_Store\n' > .gitignore
git add .gitignore
git commit -m "chore: add gitignore" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 1: Core helpers and dispatcher

**Files:**
- Create: `lib/core.sh`
- Create: `lib/port.sh`
- Create: `bin/jack`
- Create: `tests/dispatch.bats`

**Step 1: Write the failing tests**

`tests/dispatch.bats`:

```bash
#!/usr/bin/env bats

setup() {
  JACK="$BATS_TEST_DIRNAME/../bin/jack"
}

@test "no args lists themes with descriptions" {
  run "$JACK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"port"* ]]
  [[ "$output" == *"List and kill processes on TCP ports"* ]]
}

@test "core is not exposed as a theme" {
  run "$JACK"
  [[ "$output" != *"core"* ]]
  run "$JACK" core
  [ "$status" -eq 2 ]
}

@test "unknown theme exits 2" {
  run "$JACK" nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown theme"* ]]
}

@test "theme name with path characters exits 2" {
  run "$JACK" ../core
  [ "$status" -eq 2 ]
}

@test "works through a symlink" {
  ln -s "$JACK" "$BATS_TEST_TMPDIR/jack"
  run "$BATS_TEST_TMPDIR/jack"
  [ "$status" -eq 0 ]
  [[ "$output" == *"port"* ]]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/dispatch.bats`
Expected: all FAIL, `bin/jack` doesn't exist.

**Step 3: Write minimal implementation**

`lib/core.sh`:

```bash
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RESET=$'\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  RESET=''
fi

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

die_usage() {
  printf '%s\n' "$*" >&2
  exit 2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

confirm() {
  local reply
  printf '%s [y/N] ' "$1"
  read -r reply || return 1
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}
```

`lib/port.sh`:

```bash
JACK_DESC="List and kill processes on TCP ports"
```

`bin/jack`:

```bash
#!/usr/bin/env bash
set -u

src="${BASH_SOURCE[0]}"
while [ -L "$src" ]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"
  case "$src" in
    /*) ;;
    *) src="$dir/$src" ;;
  esac
done
JACK_ROOT="$(cd -P "$(dirname "$src")/.." && pwd)"

. "$JACK_ROOT/lib/core.sh"

list_themes() {
  local file name desc
  echo "usage: jack <theme> <action> [args]"
  echo
  echo "themes:"
  for file in "$JACK_ROOT"/lib/*.sh; do
    name="$(basename "$file" .sh)"
    [ "$name" = core ] && continue
    desc="$(sed -n 's/^JACK_DESC="\(.*\)"$/\1/p' "$file" | head -n 1)"
    printf '  %-10s %s\n' "$name" "$desc"
  done
}

list_actions() {
  local theme="$1"
  echo "usage: jack $theme <action> [args]"
  echo
  echo "actions:"
  sed -n "s/^${theme}_\([a-z_]*\)()[[:space:]]*{.*/  \1/p" "$JACK_ROOT/lib/$theme.sh"
}

main() {
  local theme="${1:-}" action="${2:-}"

  if [ -z "$theme" ] || [ "$theme" = -h ] || [ "$theme" = --help ]; then
    list_themes
    return 0
  fi

  case "$theme" in
    *[!a-z]*) die_usage "unknown theme: $theme" ;;
  esac
  if [ "$theme" = core ] || [ ! -f "$JACK_ROOT/lib/$theme.sh" ]; then
    die_usage "unknown theme: $theme"
  fi
  . "$JACK_ROOT/lib/$theme.sh"

  if [ -z "$action" ]; then
    list_actions "$theme"
    return 0
  fi

  case "$action" in
    *[!a-z_]*) die_usage "unknown action: $theme $action" ;;
  esac
  declare -F "${theme}_${action}" >/dev/null || die_usage "unknown action: $theme $action"

  shift 2
  "${theme}_${action}" "$@"
}

main "$@"
```

Run: `chmod +x bin/jack`

**Step 4: Run tests to verify they pass**

Run: `bats tests/dispatch.bats`
Expected: 5 tests, all PASS.

**Step 5: Commit**

```bash
git add bin lib tests
git commit -m "feat: add jack dispatcher and core helpers" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `port list`

**Files:**
- Create: `tests/test_helper.bash`
- Create: `tests/port.bats`
- Modify: `lib/port.sh`

**Step 1: Write the test helper and failing tests**

`tests/test_helper.bash`:

```bash
JACK="$BATS_TEST_DIRNAME/../bin/jack"

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

wait_for_port() {
  local i
  for i in $(seq 1 50); do
    lsof -nP -iTCP:"$1" -sTCP:LISTEN -t >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

capture_listener_pid() {
  LISTENER_PID="$(lsof -nP -iTCP:"$1" -sTCP:LISTEN -t | head -n 1)"
}

start_listener() {
  ( python3 -m http.server "$1" --bind 127.0.0.1 >/dev/null 2>&1 & )
  wait_for_port "$1"
  capture_listener_pid "$1"
}

start_stubborn_listener() {
  ( python3 -c '
import signal, socket, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(sys.argv[1])))
s.listen()
time.sleep(60)
' "$1" >/dev/null 2>&1 & )
  wait_for_port "$1"
  capture_listener_pid "$1"
}

stop_listener() {
  [ -n "${LISTENER_PID:-}" ] && kill -9 "$LISTENER_PID" 2>/dev/null
  return 0
}

port_is_free() {
  [ -z "$(lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null)" ]
}
```

The listener is started in a subshell with `&` so launchd reparents and reaps it. Otherwise a killed listener stays a zombie under bats.

`tests/port.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  PORT="$(free_port)"
}

teardown() {
  stop_listener
}

@test "list shows a listener with port, pid and command line" {
  start_listener "$PORT"
  run "$JACK" port list
  [ "$status" -eq 0 ]
  [[ "$output" == *"PORT"* ]]
  [[ "$output" == *"$PORT"* ]]
  [[ "$output" == *"$LISTENER_PID"* ]]
  [[ "$output" == *"http.server"* ]]
}

@test "list with a port filters to that port" {
  start_listener "$PORT"
  run "$JACK" port list "$PORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$LISTENER_PID"* ]]
}

@test "list with an unused port exits 1" {
  run "$JACK" port list "$PORT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no TCP listeners"* ]]
}

@test "list rejects non-numeric port" {
  run "$JACK" port list abc
  [ "$status" -eq 2 ]
}

@test "list rejects out of range ports" {
  run "$JACK" port list 0
  [ "$status" -eq 2 ]
  run "$JACK" port list 70000
  [ "$status" -eq 2 ]
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/port.bats`
Expected: all FAIL with `unknown action: port list`.

**Step 3: Write minimal implementation**

Replace `lib/port.sh`:

```bash
JACK_DESC="List and kill processes on TCP ports"

_port_validate() {
  case "$1" in
    ''|*[!0-9]*) die_usage "invalid port: $1" ;;
  esac
  if [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
    die_usage "invalid port: $1"
  fi
}

_port_rows() {
  lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk -v want="${1:-}" '
    NR > 1 {
      p = $(NF - 1)
      sub(/.*:/, "", p)
      if (want == "" || p == want) print p, $2, $3
    }' | sort -n -u -k1,1 -k2,2
}

_port_cmdline() {
  ps -o command= -p "$1" 2>/dev/null
}

port_list() {
  require_cmd lsof
  if [ $# -gt 0 ]; then
    _port_validate "$1"
  fi

  local rows port pid user
  rows="$(_port_rows "${1:-}")"
  if [ -z "$rows" ]; then
    echo "no TCP listeners${1:+ on port $1}" >&2
    return 1
  fi

  printf '%-6s %-7s %-12s %s\n' PORT PID USER COMMAND
  while read -r port pid user; do
    printf '%-6s %-7s %-12s %s\n' "$port" "$pid" "$user" "$(_port_cmdline "$pid")"
  done <<< "$rows"
}
```

**Step 4: Run tests to verify they pass**

Run: `bats tests/port.bats`
Expected: 5 tests, all PASS.

Manual check: `bin/jack port list` prints a table of your real listeners.

**Step 5: Commit**

```bash
git add lib/port.sh tests
git commit -m "feat: add port list" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `port kill`

**Files:**
- Modify: `lib/port.sh`
- Modify: `tests/port.bats`

**Step 1: Append failing tests to `tests/port.bats`**

```bash
@test "kill without a port exits 2" {
  run "$JACK" port kill
  [ "$status" -eq 2 ]
}

@test "kill rejects invalid port and unknown flag" {
  run "$JACK" port kill abc
  [ "$status" -eq 2 ]
  run "$JACK" port kill -z "$PORT"
  [ "$status" -eq 2 ]
}

@test "kill on an unused port exits 1" {
  run "$JACK" port kill -y "$PORT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing listening"* ]]
}

@test "kill -y terminates the listener" {
  start_listener "$PORT"
  run "$JACK" port kill -y "$PORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$LISTENER_PID"* ]]
  port_is_free "$PORT"
}

@test "kill aborts when the answer is n" {
  start_listener "$PORT"
  run bash -c "echo n | '$JACK' port kill '$PORT'"
  [ "$status" -eq 1 ]
  ! port_is_free "$PORT"
}

@test "kill proceeds when the answer is y" {
  start_listener "$PORT"
  run bash -c "echo y | '$JACK' port kill '$PORT'"
  [ "$status" -eq 0 ]
  port_is_free "$PORT"
}

@test "kill escalates to SIGKILL when SIGTERM is ignored" {
  start_stubborn_listener "$PORT"
  run "$JACK" port kill -y "$PORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SIGKILL"* ]]
  port_is_free "$PORT"
}
```

**Step 2: Run tests to verify they fail**

Run: `bats tests/port.bats`
Expected: the 7 new tests FAIL with `unknown action: port kill`.

**Step 3: Append implementation to `lib/port.sh`**

```bash
_port_alive() {
  local state
  state="$(ps -o stat= -p "$1" 2>/dev/null)"
  [ -n "$state" ] && [ "${state#Z}" = "$state" ]
}

_port_terminate() {
  local pid="$1" err i

  if ! err="$(kill -TERM "$pid" 2>&1)"; then
    if _port_alive "$pid"; then
      echo "${RED}$pid: $err${RESET}" >&2
      return 2
    fi
    echo "$pid already gone"
    return 0
  fi

  for i in 1 2 3 4 5 6; do
    if ! _port_alive "$pid"; then
      echo "${GREEN}$pid terminated${RESET}"
      return 0
    fi
    sleep 0.5
  done

  kill -KILL "$pid" 2>/dev/null
  sleep 0.2
  if _port_alive "$pid"; then
    echo "${RED}$pid survived SIGKILL${RESET}" >&2
    return 1
  fi
  echo "${YELLOW}$pid killed with SIGKILL${RESET}"
}

port_kill() {
  require_cmd lsof

  local port="" assume_yes=0 arg
  for arg in "$@"; do
    case "$arg" in
      -y) assume_yes=1 ;;
      -*) die_usage "unknown option: $arg" ;;
      *)
        [ -z "$port" ] || die_usage "usage: jack port kill <port> [-y]"
        port="$arg"
        ;;
    esac
  done
  [ -n "$port" ] || die_usage "usage: jack port kill <port> [-y]"
  _port_validate "$port"

  local pids pid count
  pids="$(_port_rows "$port" | awk '{print $2}' | sort -un)"
  if [ -z "$pids" ]; then
    echo "nothing listening on port $port" >&2
    return 1
  fi

  for pid in $pids; do
    printf '%s  %s  %s\n' "$pid" "$(ps -o user= -p "$pid" | tr -d ' ')" "$(_port_cmdline "$pid")"
  done

  count="$(printf '%s\n' "$pids" | wc -l | tr -d ' ')"
  if [ "$assume_yes" -eq 0 ]; then
    confirm "Kill $count process(es)?" || { echo "aborted" >&2; return 1; }
  fi

  local rc failed=0 denied=0
  for pid in $pids; do
    rc=0
    _port_terminate "$pid" || rc=$?
    case "$rc" in
      0) ;;
      2) failed=1; denied=1 ;;
      *) failed=1 ;;
    esac
  done

  if [ "$denied" -eq 1 ]; then
    echo "permission denied, try: sudo jack port kill $port -y" >&2
  fi
  return "$failed"
}
```

**Step 4: Run tests to verify they pass**

Run: `bats tests/`
Expected: all PASS. The SIGKILL test takes about 3 seconds.

Manual EPERM check: find a root-owned listener with `bin/jack port list`, run `bin/jack port kill <port> -y` without sudo. Expected: permission error, sudo hint, exit 1. Do not run it with sudo against a system service.

**Step 5: Commit**

```bash
git add lib/port.sh tests/port.bats
git commit -m "feat: add port kill with SIGTERM to SIGKILL escalation" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Action listing, README, install

**Files:**
- Modify: `tests/dispatch.bats`
- Create: `README.md`

**Step 1: Append failing tests to `tests/dispatch.bats`**

```bash
@test "theme alone lists public actions only" {
  run "$JACK" port
  [ "$status" -eq 0 ]
  [[ "$output" == *"list"* ]]
  [[ "$output" == *"kill"* ]]
  [[ "$output" != *"validate"* ]]
  [[ "$output" != *"cmdline"* ]]
}

@test "unknown action exits 2" {
  run "$JACK" port nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown action"* ]]
}

@test "helper functions are not callable as actions" {
  run "$JACK" port _validate
  [ "$status" -eq 2 ]
}
```

**Step 2: Run tests**

Run: `bats tests/dispatch.bats`
Expected: PASS. The behavior already exists from Task 1 and 3. If any fail, fix `bin/jack` before moving on.

**Step 3: Write `README.md`**

````markdown
# jack

Local dev toolkit. `jack <theme> <action> [args]`.

## Install

```bash
ln -s "$PWD/bin/jack" /usr/local/bin/jack
```

## Use

```bash
jack                    # list themes
jack port               # list actions
jack port list [port]
jack port kill <port> [-y]
```

## Add a theme

Create `lib/<theme>.sh` with a `JACK_DESC="..."` line and functions named `<theme>_<action>`. Prefix helpers with `_<theme>_`. Nothing else needs editing.

## Test

```bash
brew install bats-core
bats tests/
```
````

**Step 4: Install and smoke test**

Run: `ln -s "$PWD/bin/jack" /usr/local/bin/jack && jack && jack port list`
Expected: theme list, then a table of listeners.

**Step 5: Commit**

```bash
git add README.md tests/dispatch.bats
git commit -m "docs: add README and action listing tests" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
