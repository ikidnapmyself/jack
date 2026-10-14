# jack gist themes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add docker, git, npm, mysql, mac and ubuntu themes to jack, plus `cheat` and `alias` themes that read action metadata from the theme files.

**Architecture:** Each action declares `JACK_DOC_<action>` and optionally `JACK_ALIAS_<action>` as plain assignments in its theme file. Helpers in `lib/core.sh` read them with `sed`, never by sourcing. The dispatcher maps `-` in action names to `_`. Design: `docs/plans/2026-10-14-jack-themes-design.md`.

**Tech Stack:** bash 3.2 compatible, bats-core. External commands are stubbed with fake executables on `PATH`.

## Conventions

- Work on a branch off `docs/jack-themes-design`, for example `feat/jack-themes`.
- No comments in code. No bash 4 features. No empty-array expansion under `set -u`.
- Every commit message ends with the trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Commands below show only the subject line.
- Run a single file with `bats tests/<file>.bats`, everything with `bats tests/`.
- Deviation from the design doc, `mysql dump` refuses to overwrite an existing file and removes a partial file when `mysqldump` fails. `git reset-remote` fetches the upstream's remote instead of hardcoding `origin`. `ubuntu flush-dns` uses `service <name> restart` instead of `/etc/init.d/<name>` so it can be stubbed.
- Aliases are given only to the cross-platform themes `docker`, `git`, `npm` and `mysql`. Eval-ing aliases for the other OS's themes would be noise.

---

### Task 1: Test stubs and core prompt helpers

**Files:**
- Modify: `tests/test_helper.bash`
- Modify: `lib/core.sh`
- Create: `tests/core.bats`

**Step 1: Add stub helpers**

Append to `tests/test_helper.bash`:

```bash

setup_stubs() {
  STUB_DIR="$BATS_TEST_TMPDIR/stubs"
  STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  mkdir -p "$STUB_DIR"
  : > "$STUB_LOG"
  PATH="$STUB_DIR:$PATH"
  export STUB_LOG
}

stub_cmd() {
  local name="$1" body="${2:-}"
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$STUB_LOG"\n%s\n' "$name" "$body" > "$STUB_DIR/$name"
  chmod +x "$STUB_DIR/$name"
}

logged() {
  grep -qxF -- "$1" "$STUB_LOG"
}

not_logged_like() {
  ! grep -q -- "$1" "$STUB_LOG"
}
```

**Step 2: Write the failing tests**

Create `tests/core.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  JACK_ROOT="$BATS_TEST_DIRNAME/.."
  . "$JACK_ROOT/lib/core.sh"
  setup_stubs
}

@test "confirm_unless_yes skips the prompt when assume is 1" {
  run confirm_unless_yes "Go?" 1
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "confirm_unless_yes aborts on n" {
  run confirm_unless_yes "Go?" 0 <<< "n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"aborted"* ]]
}

@test "confirm_unless_yes proceeds on y" {
  run confirm_unless_yes "Go?" 0 <<< "y"
  [ "$status" -eq 0 ]
}

@test "parse_yes_only sets ASSUME_YES" {
  parse_yes_only "usage" -y
  [ "$ASSUME_YES" -eq 1 ]
  parse_yes_only "usage"
  [ "$ASSUME_YES" -eq 0 ]
}

@test "parse_yes_only rejects other args with exit 2" {
  run parse_yes_only "jack x [-y]" nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: jack x [-y]"* ]]
}

@test "require_root dies with a sudo hint when not root" {
  stub_cmd id 'echo 501'
  run require_root mac flush-dns
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo jack mac flush-dns"* ]]
}

@test "require_root passes for uid 0" {
  stub_cmd id 'echo 0'
  run require_root mac flush-dns
  [ "$status" -eq 0 ]
}
```

**Step 3: Run to verify failure**

Run: `bats tests/core.bats`
Expected: all FAIL with "command not found" for the helpers.

**Step 4: Implement**

Append to `lib/core.sh`:

```bash

confirm_unless_yes() {
  [ "$2" -eq 1 ] && return 0
  confirm "$1" || { echo "aborted" >&2; return 1; }
}

parse_yes_only() {
  local usage="$1" arg
  shift
  ASSUME_YES=0
  for arg in "$@"; do
    case "$arg" in
      -y) ASSUME_YES=1 ;;
      *) die_usage "usage: $usage" ;;
    esac
  done
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "needs root, run: sudo jack $*"
}
```

**Step 5: Run to verify pass, then commit**

Run: `bats tests/`
Expected: all PASS.

```bash
git add tests/test_helper.bash tests/core.bats lib/core.sh
git commit -m "feat: add stub helpers and core prompt helpers"
```

---

### Task 2: Move port validation into core

**Files:**
- Modify: `lib/core.sh`
- Modify: `lib/port.sh`
- Modify: `tests/core.bats`

**Step 1: Write the failing tests**

Append to `tests/core.bats`:

```bash

@test "validate_port accepts the range edges" {
  run validate_port 1
  [ "$status" -eq 0 ]
  run validate_port 65535
  [ "$status" -eq 0 ]
}

@test "validate_port rejects bad ports with exit 2" {
  local p
  for p in 0 65536 080 abc "" 1234567; do
    run validate_port "$p"
    [ "$status" -eq 2 ]
  done
}
```

**Step 2: Run to verify failure**

Run: `bats tests/core.bats`
Expected: the two new tests FAIL with "command not found".

**Step 3: Implement**

Append to `lib/core.sh`:

```bash

validate_port() {
  case "$1" in
    ''|*[!0-9]*|0*|??????*) die_usage "invalid port: $1" ;;
  esac
  if [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
    die_usage "invalid port: $1"
  fi
}
```

In `lib/port.sh`, delete the whole `_port_validate` function and the blank line after it, then replace both `_port_validate` call sites with `validate_port`.

**Step 4: Run to verify pass, then commit**

Run: `bats tests/`
Expected: all PASS, including the existing port tests that reject bad ports.

```bash
git add lib/core.sh lib/port.sh tests/core.bats
git commit -m "refactor: share port validation through core"
```

---

### Task 3: Shared ssh key helper

**Files:**
- Modify: `lib/core.sh`
- Modify: `tests/core.bats`

**Step 1: Write the failing tests**

Append to `tests/core.bats`:

```bash

@test "ssh_keygen_for creates an ed25519 key for the email" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  stub_cmd ssh-keygen ''
  run ssh_keygen_for mac me@example.com
  [ "$status" -eq 0 ]
  logged "ssh-keygen -t ed25519 -C me@example.com -f $HOME/.ssh/id_ed25519"
}

@test "ssh_keygen_for refuses to overwrite an existing key" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/id_ed25519"
  stub_cmd ssh-keygen ''
  run ssh_keygen_for mac me@example.com
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
  not_logged_like "^ssh-keygen"
}

@test "ssh_keygen_for without an email exits 2" {
  run ssh_keygen_for mac
  [ "$status" -eq 2 ]
  [[ "$output" == *"jack mac ssh-key <email>"* ]]
}
```

**Step 2: Run to verify failure**

Run: `bats tests/core.bats`
Expected: the three new tests FAIL with "command not found".

**Step 3: Implement**

Append to `lib/core.sh`:

```bash

ssh_keygen_for() {
  local theme="$1"
  shift
  { [ $# -eq 1 ] && [ -n "$1" ]; } || die_usage "usage: jack $theme ssh-key <email>"
  require_cmd ssh-keygen
  local path="$HOME/.ssh/id_ed25519"
  [ ! -e "$path" ] || die "$path already exists"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$1" -f "$path"
  echo "public key: $path.pub"
}
```

**Step 4: Run to verify pass, then commit**

Run: `bats tests/core.bats`
Expected: all PASS.

```bash
git add lib/core.sh tests/core.bats
git commit -m "feat: add shared ssh key helper"
```

---

### Task 4: Metadata helpers, dispatcher and port docs

**Files:**
- Modify: `lib/core.sh`
- Modify: `bin/jack`
- Modify: `lib/port.sh`
- Modify: `tests/dispatch.bats`
- Create: `tests/meta.bats`

**Step 1: Write the failing tests**

Create `tests/meta.bats`:

```bash
#!/usr/bin/env bats

setup() {
  JACK_ROOT="$BATS_TEST_DIRNAME/.."
  . "$JACK_ROOT/lib/core.sh"
}

@test "every public action has a JACK_DOC" {
  local theme act missing=""
  for theme in $(jack_themes); do
    for act in $(jack_actions "$theme"); do
      [ -n "$(jack_meta "$theme" DOC "$act")" ] || missing="$missing $theme/$act"
    done
  done
  [ -z "$missing" ] || { echo "missing JACK_DOC:$missing"; return 1; }
}

@test "aliases are unique and well formed" {
  local theme act name seen=" "
  for theme in $(jack_themes); do
    for act in $(jack_actions "$theme"); do
      name="$(jack_meta "$theme" ALIAS "$act")"
      [ -n "$name" ] || continue
      case "$name" in
        [a-z]*) ;;
        *) echo "bad alias: $name"; return 1 ;;
      esac
      case "$name" in
        *[!a-z0-9]*) echo "bad alias: $name"; return 1 ;;
      esac
      case "$seen" in
        *" $name "*) echo "duplicate alias: $name"; return 1 ;;
      esac
      seen="$seen$name "
    done
  done
}
```

Append to `tests/dispatch.bats`:

```bash

@test "theme alone shows action docs" {
  run "$JACK" port
  [[ "$output" == *"Kill whatever listens on a port"* ]]
}

@test "hyphenated action runs the underscore function" {
  mkdir -p "$BATS_TEST_TMPDIR/root"
  cp -R "$BATS_TEST_DIRNAME/../bin" "$BATS_TEST_DIRNAME/../lib" "$BATS_TEST_TMPDIR/root/"
  printf 'JACK_DESC="fixture"\nJACK_DOC_two_words="Say ok"\nfx_two_words() { echo ok; }\n' > "$BATS_TEST_TMPDIR/root/lib/fx.sh"
  run "$BATS_TEST_TMPDIR/root/bin/jack" fx two-words
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
  run "$BATS_TEST_TMPDIR/root/bin/jack" fx
  [[ "$output" == *"two-words"* ]]
  [[ "$output" == *"Say ok"* ]]
}
```

**Step 2: Run to verify failure**

Run: `bats tests/meta.bats tests/dispatch.bats`
Expected: FAIL with "jack_themes: command not found" and the two new dispatch tests failing.

**Step 3: Implement core helpers**

Append to `lib/core.sh`:

```bash

jack_themes() {
  local file name
  for file in "$JACK_ROOT"/lib/*.sh; do
    name="$(basename "$file" .sh)"
    [ "$name" = core ] || echo "$name"
  done
}

jack_actions() {
  sed -n "s/^$1_\([a-z_]*\)()[[:space:]]*{.*/\1/p" "$JACK_ROOT/lib/$1.sh"
}

jack_meta() {
  sed -n "s/^JACK_$2_$3=\"\(.*\)\"\$/\1/p" "$JACK_ROOT/lib/$1.sh" | head -n 1
}

jack_print_actions() {
  local act
  for act in $(jack_actions "$1"); do
    printf '  %-18s %s\n' "$(printf %s "$act" | tr _ -)" "$(jack_meta "$1" DOC "$act")"
  done
}
```

**Step 4: Update the dispatcher**

In `bin/jack`, replace `list_themes` and `list_actions` with:

```bash
list_themes() {
  local name desc
  echo "usage: jack <theme> <action> [args]"
  echo
  echo "themes:"
  for name in $(jack_themes); do
    desc="$(sed -n 's/^JACK_DESC="\(.*\)"$/\1/p' "$JACK_ROOT/lib/$name.sh" | head -n 1)"
    printf '  %-10s %s\n' "$name" "$desc"
  done
}

list_actions() {
  echo "usage: jack $1 <action> [args]"
  echo
  echo "actions:"
  jack_print_actions "$1"
}
```

In `main`, change `local theme="${1:-}" action="${2:-}"` to `local theme="${1:-}" action="${2:-}" fn`, and replace the action validation and call with:

```bash
  case "$action" in
    *[!a-z_-]*) die_usage "unknown action: $theme $action" ;;
  esac
  fn="${theme}_$(printf %s "$action" | tr - _)"
  declare -F "$fn" >/dev/null || die_usage "unknown action: $theme $action"

  shift 2
  "$fn" "$@"
```

**Step 5: Add port docs**

In `lib/port.sh`, directly under the `JACK_DESC` line add:

```bash
JACK_DOC_list="List TCP listeners, optionally for one port"
JACK_DOC_kill="Kill whatever listens on a port, SIGTERM then SIGKILL"
```

**Step 6: Run to verify pass, then commit**

Run: `bats tests/`
Expected: all PASS.

```bash
git add lib/core.sh bin/jack lib/port.sh tests/dispatch.bats tests/meta.bats
git commit -m "feat: add action metadata and hyphenated actions"
```

---

### Task 5: cheat theme

**Files:**
- Create: `lib/cheat.sh`
- Create: `tests/cheat.bats`

**Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load test_helper

@test "list shows every theme with its actions and docs" {
  run "$JACK" cheat list
  [ "$status" -eq 0 ]
  [[ "$output" == *"port"* ]]
  [[ "$output" == *"Kill whatever listens on a port"* ]]
}

@test "list never shows core" {
  run "$JACK" cheat list
  [[ "$output" != *"core"* ]]
}

@test "list with a theme shows only that theme" {
  run "$JACK" cheat list port
  [ "$status" -eq 0 ]
  [[ "$output" == *"kill"* ]]
  [[ "$output" != *"cheat"* ]]
}

@test "list with an unknown theme exits 2" {
  run "$JACK" cheat list nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown theme"* ]]
}
```

**Step 2: Run to verify failure**

Run: `bats tests/cheat.bats`
Expected: FAIL with "unknown theme: cheat".

**Step 3: Implement**

Create `lib/cheat.sh`:

```bash
JACK_DESC="Browse every theme's actions"
JACK_DOC_list="List actions with descriptions, optionally for one theme"

cheat_list() {
  local only="${1:-}" theme
  if [ -n "$only" ]; then
    case "$only" in
      *[!a-z]*) die_usage "unknown theme: $only" ;;
    esac
    [ "$only" != core ] && [ -f "$JACK_ROOT/lib/$only.sh" ] || die_usage "unknown theme: $only"
  fi
  for theme in $(jack_themes); do
    [ -z "$only" ] || [ "$only" = "$theme" ] || continue
    echo "$theme"
    jack_print_actions "$theme"
  done
}
```

**Step 4: Run to verify pass, then commit**

Run: `bats tests/`
Expected: all PASS.

```bash
git add lib/cheat.sh tests/cheat.bats
git commit -m "feat: add cheat theme"
```

---

### Task 6: alias theme

**Files:**
- Create: `lib/alias.sh`
- Create: `tests/alias.bats`

**Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/root"
  cp -R "$BATS_TEST_DIRNAME/../bin" "$BATS_TEST_DIRNAME/../lib" "$BATS_TEST_TMPDIR/root/"
  printf 'JACK_DESC="fixture"\nJACK_DOC_two_words="Say ok"\nJACK_ALIAS_two_words="twow"\nJACK_DOC_plain="No alias"\nfx_two_words() { echo ok; }\nfx_plain() { echo ok; }\n' > "$BATS_TEST_TMPDIR/root/lib/fx.sh"
  FXJACK="$BATS_TEST_TMPDIR/root/bin/jack"
}

@test "print emits an alias line per JACK_ALIAS" {
  run "$FXJACK" alias print
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias twow='jack fx two-words'"* ]]
}

@test "print skips actions without an alias" {
  run "$FXJACK" alias print
  [[ "$output" != *"plain"* ]]
}

@test "print output can be eval-ed" {
  run bash -c 'eval "$("$1" alias print)" && alias twow' _ "$FXJACK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jack fx two-words"* ]]
}
```

**Step 2: Run to verify failure**

Run: `bats tests/alias.bats`
Expected: FAIL with "unknown theme: alias".

**Step 3: Implement**

Create `lib/alias.sh`:

```bash
JACK_DESC="Emit shell aliases for jack actions"
JACK_DOC_print="Print one alias line per aliased action, for eval in your shell rc"

alias_print() {
  local theme act name
  for theme in $(jack_themes); do
    for act in $(jack_actions "$theme"); do
      name="$(jack_meta "$theme" ALIAS "$act")"
      [ -n "$name" ] || continue
      printf "alias %s='jack %s %s'\n" "$name" "$theme" "$(printf %s "$act" | tr _ -)"
    done
  done
}
```

**Step 4: Run to verify pass, then commit**

Run: `bats tests/`
Expected: all PASS.

```bash
git add lib/alias.sh tests/alias.bats
git commit -m "feat: add alias theme"
```

---

### Task 7: docker theme

**Files:**
- Create: `lib/docker.sh`
- Create: `tests/docker.bats`

**Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  setup_stubs
}

@test "stop -y stops running containers" {
  stub_cmd docker 'case "$1" in ps) printf "abc\ndef\n" ;; esac'
  run "$JACK" docker stop -y
  [ "$status" -eq 0 ]
  logged "docker ps -q"
  logged "docker stop abc def"
}

@test "stop proceeds when the prompt is accepted" {
  stub_cmd docker 'case "$1" in ps) echo abc ;; esac'
  run "$JACK" docker stop <<< "y"
  [ "$status" -eq 0 ]
  logged "docker stop abc"
}

@test "stop aborts when the prompt is declined" {
  stub_cmd docker 'case "$1" in ps) echo abc ;; esac'
  run "$JACK" docker stop <<< "n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"aborted"* ]]
  not_logged_like "^docker stop"
}

@test "stop with nothing running says so" {
  stub_cmd docker ''
  run "$JACK" docker stop -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to stop"* ]]
  not_logged_like "^docker stop"
}

@test "stop rejects unknown options" {
  stub_cmd docker ''
  run "$JACK" docker stop --force
  [ "$status" -eq 2 ]
}

@test "rm -y removes exited containers" {
  stub_cmd docker 'case "$1" in ps) printf "abc\ndef\n" ;; esac'
  run "$JACK" docker rm -y
  [ "$status" -eq 0 ]
  logged "docker ps -aq -f status=exited"
  logged "docker rm abc def"
}

@test "rm aborts when declined" {
  stub_cmd docker 'case "$1" in ps) echo abc ;; esac'
  run "$JACK" docker rm <<< "n"
  [ "$status" -eq 1 ]
  not_logged_like "^docker rm"
}

@test "rm with nothing stopped says so" {
  stub_cmd docker ''
  run "$JACK" docker rm -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to remove"* ]]
}

@test "prune -y runs a forced system prune" {
  stub_cmd docker ''
  run "$JACK" docker prune -y
  [ "$status" -eq 0 ]
  logged "docker system prune -f"
}

@test "prune --volumes passes the flag through" {
  stub_cmd docker ''
  run "$JACK" docker prune --volumes -y
  [ "$status" -eq 0 ]
  logged "docker system prune -f --volumes"
}

@test "prune aborts when declined" {
  stub_cmd docker ''
  run "$JACK" docker prune <<< "n"
  [ "$status" -eq 1 ]
  not_logged_like "^docker system"
}

@test "ps shows compose services" {
  stub_cmd docker-compose ''
  run "$JACK" docker ps
  [ "$status" -eq 0 ]
  logged "docker-compose ps"
}

@test "restart passes the service to docker-compose" {
  stub_cmd docker-compose ''
  run "$JACK" docker restart elasticsearch
  [ "$status" -eq 0 ]
  logged "docker-compose restart elasticsearch"
}

@test "restart without a service exits 2" {
  stub_cmd docker-compose ''
  run "$JACK" docker restart
  [ "$status" -eq 2 ]
}

@test "restart rejects a bad service name" {
  stub_cmd docker-compose ''
  run "$JACK" docker restart 'a;b'
  [ "$status" -eq 2 ]
  not_logged_like "^docker-compose"
}
```

**Step 2: Run to verify failure**

Run: `bats tests/docker.bats`
Expected: FAIL with "unknown theme: docker".

**Step 3: Implement**

Create `lib/docker.sh`:

```bash
JACK_DESC="Docker and docker-compose chores"
JACK_DOC_stop="Stop all running containers"
JACK_ALIAS_stop="dstop"
JACK_DOC_rm="Remove all exited containers"
JACK_ALIAS_rm="drm"
JACK_DOC_prune="Remove unused containers, networks, images and cache, --volumes adds volumes"
JACK_ALIAS_prune="dprune"
JACK_DOC_ps="Show this project's compose services"
JACK_ALIAS_ps="dps"
JACK_DOC_restart="Restart one compose service"
JACK_ALIAS_restart="drestart"

docker_stop() {
  parse_yes_only "jack docker stop [-y]" "$@"
  require_cmd docker
  local ids count
  ids="$(docker ps -q)"
  if [ -z "$ids" ]; then
    echo "nothing to stop"
    return 0
  fi
  count="$(printf '%s\n' "$ids" | wc -l | tr -d ' ')"
  confirm_unless_yes "Stop $count container(s)?" "$ASSUME_YES" || return 1
  docker stop $ids
}

docker_rm() {
  parse_yes_only "jack docker rm [-y]" "$@"
  require_cmd docker
  local ids count
  ids="$(docker ps -aq -f status=exited)"
  if [ -z "$ids" ]; then
    echo "nothing to remove"
    return 0
  fi
  count="$(printf '%s\n' "$ids" | wc -l | tr -d ' ')"
  confirm_unless_yes "Remove $count container(s)?" "$ASSUME_YES" || return 1
  docker rm $ids
}

docker_prune() {
  local volumes="" assume_yes=0 arg
  for arg in "$@"; do
    case "$arg" in
      -y) assume_yes=1 ;;
      --volumes) volumes="--volumes" ;;
      *) die_usage "usage: jack docker prune [--volumes] [-y]" ;;
    esac
  done
  require_cmd docker
  confirm_unless_yes "Prune unused Docker objects${volumes:+ including volumes}?" "$assume_yes" || return 1
  docker system prune -f $volumes
}

docker_ps() {
  [ $# -eq 0 ] || die_usage "usage: jack docker ps"
  require_cmd docker-compose
  docker-compose ps
}

docker_restart() {
  [ $# -eq 1 ] || die_usage "usage: jack docker restart <service>"
  case "$1" in
    ''|-*|*[!A-Za-z0-9_.-]*) die_usage "invalid service: $1" ;;
  esac
  require_cmd docker-compose
  docker-compose restart "$1"
}
```

**Step 4: Run to verify pass, then commit**

Run: `bats tests/`
Expected: all PASS, including the meta tests.

```bash
git add lib/docker.sh tests/docker.bats
git commit -m "feat: add docker theme"
```

---

### Task 8: git theme

**Files:**
- Create: `lib/git.sh`
- Create: `tests/git.bats`

**Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git init -q --bare -b main "$BATS_TEST_TMPDIR/remote.git"
  git init -q -b main "$BATS_TEST_TMPDIR/a"
  cd "$BATS_TEST_TMPDIR/a"
  git remote add origin "$BATS_TEST_TMPDIR/remote.git"
  echo one > f
  git add f
  git commit -q -m one
  git push -q -u origin main
  git clone -q "$BATS_TEST_TMPDIR/remote.git" "$BATS_TEST_TMPDIR/b"
  git -C "$BATS_TEST_TMPDIR/b" commit -q --allow-empty -m two
  git -C "$BATS_TEST_TMPDIR/b" push -q origin main
  echo local > g
  git add g
  git commit -q -m local
}

@test "reset-remote -y moves to upstream and keeps a backup branch" {
  old="$(git rev-parse HEAD)"
  run "$JACK" git reset-remote -y
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]
  [ "$(git for-each-ref --format='%(objectname)' refs/heads/backup)" = "$old" ]
}

@test "reset-remote aborts when declined" {
  old="$(git rev-parse HEAD)"
  run "$JACK" git reset-remote <<< "n"
  [ "$status" -eq 1 ]
  [ "$(git rev-parse HEAD)" = "$old" ]
  [ -z "$(git for-each-ref refs/heads/backup)" ]
}

@test "reset-remote warns about a dirty tree" {
  echo changed >> f
  run "$JACK" git reset-remote -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"dirty"* ]]
}

@test "reset-remote without an upstream exits 1" {
  git switch -q -c lone
  run "$JACK" git reset-remote -y
  [ "$status" -eq 1 ]
  [[ "$output" == *"no upstream"* ]]
}

@test "remote-url shows the origin remote" {
  run "$JACK" git remote-url
  [ "$status" -eq 0 ]
  [[ "$output" == *"remote.git"* ]]
}

@test "submodules updates recursively" {
  setup_stubs
  stub_cmd git ''
  run "$JACK" git submodules
  [ "$status" -eq 0 ]
  logged "git submodule update --init --recursive"
}
```

**Step 2: Run to verify failure**

Run: `bats tests/git.bats`
Expected: FAIL with "unknown theme: git".

**Step 3: Implement**

Create `lib/git.sh`:

```bash
JACK_DESC="Git chores"
JACK_DOC_reset_remote="Hard reset the branch to its upstream after saving a backup branch"
JACK_ALIAS_reset_remote="greset"
JACK_DOC_remote_url="Show the origin remote"
JACK_ALIAS_remote_url="gurl"
JACK_DOC_submodules="Init and update submodules recursively"
JACK_ALIAS_submodules="gsub"

git_reset_remote() {
  parse_yes_only "jack git reset-remote [-y]" "$@"
  require_cmd git
  local branch upstream backup
  branch="$(git symbolic-ref --short -q HEAD)" || die "detached HEAD, nothing to reset"
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || die "$branch has no upstream"
  git fetch "${upstream%%/*}"
  backup="backup/$branch-$(date +%Y%m%d-%H%M%S)"
  if [ -n "$(git status --porcelain)" ]; then
    echo "${YELLOW}working tree is dirty, uncommitted changes will be lost${RESET}"
  fi
  confirm_unless_yes "Reset $branch to $upstream? Backup: $backup" "$ASSUME_YES" || return 1
  git branch "$backup"
  git reset --hard "$upstream"
}

git_remote_url() {
  [ $# -eq 0 ] || die_usage "usage: jack git remote-url"
  require_cmd git
  git remote show origin
}

git_submodules() {
  [ $# -eq 0 ] || die_usage "usage: jack git submodules"
  require_cmd git
  git submodule update --init --recursive
}
```

**Step 4: Run to verify pass, then commit**

Run: `bats tests/`
Expected: all PASS. If `git init -b` is rejected, the machine has git older than 2.28 and the test setup needs `git symbolic-ref HEAD refs/heads/main` after init.

```bash
git add lib/git.sh tests/git.bats
git commit -m "feat: add git theme"
```

---

### Task 9: npm theme

**Files:**
- Create: `lib/npm.sh`
- Create: `tests/npm.bats`

**Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  setup_stubs
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  stub_cmd npm ''
}

@test "cache-clear forces a cache clear" {
  run "$JACK" npm cache-clear
  [ "$status" -eq 0 ]
  logged "npm cache clear --force"
}

@test "global-setup -y creates the dir, sets the prefix and edits the profile" {
  run "$JACK" npm global-setup -y
  [ "$status" -eq 0 ]
  [ -d "$HOME/.npm-global" ]
  logged "npm config set prefix $HOME/.npm-global"
  grep -qxF 'export PATH=~/.npm-global/bin:$PATH' "$HOME/.profile"
}

@test "global-setup twice adds the PATH line once" {
  run "$JACK" npm global-setup -y
  run "$JACK" npm global-setup -y
  [ "$status" -eq 0 ]
  [ "$(grep -c 'npm-global' "$HOME/.profile")" -eq 1 ]
}

@test "global-setup aborts when declined and touches nothing" {
  run "$JACK" npm global-setup <<< "n"
  [ "$status" -eq 1 ]
  [ ! -e "$HOME/.profile" ]
  [ ! -e "$HOME/.npm-global" ]
  not_logged_like "^npm config"
}
```

**Step 2: Run to verify failure**

Run: `bats tests/npm.bats`
Expected: FAIL with "unknown theme: npm".

**Step 3: Implement**

Create `lib/npm.sh`:

```bash
JACK_DESC="NPM chores"
JACK_DOC_cache_clear="Force-clear the npm cache"
JACK_ALIAS_cache_clear="npmcc"
JACK_DOC_global_setup="Point global installs at ~/.npm-global and add it to PATH in ~/.profile"

npm_cache_clear() {
  [ $# -eq 0 ] || die_usage "usage: jack npm cache-clear"
  require_cmd npm
  npm cache clear --force
}

npm_global_setup() {
  parse_yes_only "jack npm global-setup [-y]" "$@"
  require_cmd npm
  local dir="$HOME/.npm-global" profile="$HOME/.profile"
  local line='export PATH=~/.npm-global/bin:$PATH'
  confirm_unless_yes "Set npm prefix to $dir and edit $profile?" "$ASSUME_YES" || return 1
  mkdir -p "$dir"
  npm config set prefix "$dir"
  if grep -qxF "$line" "$profile" 2>/dev/null; then
    echo "$profile already exports $dir/bin"
  else
    printf '%s\n' "$line" >> "$profile"
    echo "added PATH export to $profile"
  fi
}
```

**Step 4: Run to verify pass, then commit**

Run: `bats tests/`
Expected: all PASS.

```bash
git add lib/npm.sh tests/npm.bats
git commit -m "feat: add npm theme"
```

---

### Task 10: mysql theme

**Files:**
- Create: `lib/mysql.sh`
- Create: `tests/mysql.bats`

**Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  setup_stubs
  cd "$BATS_TEST_TMPDIR"
  export USER=alice
  stub_cmd mysqldump 'echo "-- dump"'
}

@test "dump writes the dump to the file" {
  run "$JACK" mysql dump mydb out.sql
  [ "$status" -eq 0 ]
  logged "mysqldump -u alice -p mydb"
  [ "$(cat out.sql)" = "-- dump" ]
}

@test "dump passes tables and an explicit user" {
  run "$JACK" mysql dump -u bob mydb out.sql users orders
  [ "$status" -eq 0 ]
  logged "mysqldump -u bob -p mydb users orders"
}

@test "dump accepts -u after the positional args" {
  run "$JACK" mysql dump mydb out.sql users -u bob
  [ "$status" -eq 0 ]
  logged "mysqldump -u bob -p mydb users"
}

@test "dump without enough args exits 2" {
  run "$JACK" mysql dump mydb
  [ "$status" -eq 2 ]
}

@test "dump rejects unknown options" {
  run "$JACK" mysql dump --evil mydb out.sql
  [ "$status" -eq 2 ]
}

@test "dump rejects a bad database name" {
  run "$JACK" mysql dump 'a;b' out.sql
  [ "$status" -eq 2 ]
  not_logged_like "^mysqldump"
}

@test "dump refuses to overwrite an existing file" {
  echo keep > out.sql
  run "$JACK" mysql dump mydb out.sql
  [ "$status" -eq 1 ]
  [[ "$output" == *"exists"* ]]
  [ "$(cat out.sql)" = "keep" ]
}

@test "dump removes the partial file when mysqldump fails" {
  stub_cmd mysqldump 'exit 1'
  run "$JACK" mysql dump mydb out.sql
  [ "$status" -eq 1 ]
  [ ! -e out.sql ]
}
```

**Step 2: Run to verify failure**

Run: `bats tests/mysql.bats`
Expected: FAIL with "unknown theme: mysql".

**Step 3: Implement**

Create `lib/mysql.sh`:

```bash
JACK_DESC="MySQL chores"
JACK_DOC_dump="Dump a database or chosen tables to a file with mysqldump"
JACK_ALIAS_dump="mydump"

mysql_dump() {
  local usage="usage: jack mysql dump <db> <file> [table...] [-u user]"
  local user="${USER:-root}" n=$#
  while [ "$n" -gt 0 ]; do
    case "$1" in
      -u)
        [ $# -ge 2 ] || die_usage "$usage"
        user="$2"
        shift 2
        n=$((n - 2))
        ;;
      -*) die_usage "$usage" ;;
      *)
        set -- "$@" "$1"
        shift
        n=$((n - 1))
        ;;
    esac
  done
  [ $# -ge 2 ] || die_usage "$usage"
  local db="$1" file="$2"
  shift 2
  case "$db" in
    ''|-*|*[!A-Za-z0-9_.$-]*) die_usage "invalid database: $db" ;;
  esac
  require_cmd mysqldump
  [ ! -e "$file" ] || die "$file exists"
  mysqldump -u "$user" -p "$db" "$@" > "$file" || { rm -f "$file"; die "mysqldump failed"; }
}
```

**Step 4: Run to verify pass, then commit**

Run: `bats tests/`
Expected: all PASS.

```bash
git add lib/mysql.sh tests/mysql.bats
git commit -m "feat: add mysql theme"
```

---

### Task 11: mac theme

**Files:**
- Create: `lib/mac.sh`
- Create: `tests/mac.bats`

**Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  setup_stubs
}

@test "flush-dns needs root" {
  stub_cmd id 'echo 501'
  stub_cmd killall ''
  run "$JACK" mac flush-dns
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo jack mac flush-dns"* ]]
  not_logged_like "^killall"
}

@test "flush-dns signals mDNSResponder as root" {
  stub_cmd id 'echo 0'
  stub_cmd killall ''
  run "$JACK" mac flush-dns
  [ "$status" -eq 0 ]
  logged "killall -HUP mDNSResponder"
}

@test "nginx-reload needs root" {
  stub_cmd id 'echo 501'
  stub_cmd nginx ''
  run "$JACK" mac nginx-reload
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo jack mac nginx-reload"* ]]
}

@test "nginx-reload reloads as root" {
  stub_cmd id 'echo 0'
  stub_cmd nginx ''
  run "$JACK" mac nginx-reload
  [ "$status" -eq 0 ]
  logged "nginx -s reload"
}

@test "ssh-key uses the shared helper" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  stub_cmd ssh-keygen ''
  run "$JACK" mac ssh-key me@example.com
  [ "$status" -eq 0 ]
  logged "ssh-keygen -t ed25519 -C me@example.com -f $HOME/.ssh/id_ed25519"
}
```

**Step 2: Run to verify failure**

Run: `bats tests/mac.bats`
Expected: FAIL with "unknown theme: mac".

**Step 3: Implement**

Create `lib/mac.sh`:

```bash
JACK_DESC="macOS chores"
JACK_DOC_flush_dns="Flush the DNS cache, needs root"
JACK_DOC_nginx_reload="Reload nginx, needs root"
JACK_DOC_ssh_key="Generate an ed25519 SSH key for an email"

mac_flush_dns() {
  [ $# -eq 0 ] || die_usage "usage: jack mac flush-dns"
  require_root mac flush-dns
  killall -HUP mDNSResponder
}

mac_nginx_reload() {
  [ $# -eq 0 ] || die_usage "usage: jack mac nginx-reload"
  require_root mac nginx-reload
  require_cmd nginx
  nginx -s reload
}

mac_ssh_key() {
  ssh_keygen_for mac "$@"
}
```

**Step 4: Run to verify pass, then commit**

Run: `bats tests/`
Expected: all PASS.

```bash
git add lib/mac.sh tests/mac.bats
git commit -m "feat: add mac theme"
```

---

### Task 12: ubuntu theme, network and info actions

**Files:**
- Create: `lib/ubuntu.sh`
- Create: `tests/ubuntu.bats`

**Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  setup_stubs
}

@test "flush-dns needs root" {
  stub_cmd id 'echo 501'
  stub_cmd service ''
  run "$JACK" ubuntu flush-dns
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo jack ubuntu flush-dns"* ]]
  not_logged_like "^service"
}

@test "flush-dns restarts named and nscd as root" {
  stub_cmd id 'echo 0'
  stub_cmd service ''
  run "$JACK" ubuntu flush-dns
  [ "$status" -eq 0 ]
  logged "service named restart"
  logged "service nscd restart"
}

@test "ports lists listening tcp sockets" {
  stub_cmd ss 'echo LISTEN'
  run "$JACK" ubuntu ports
  [ "$status" -eq 0 ]
  logged "ss -lntp"
}

@test "port-test reports an open port" {
  stub_cmd nc ''
  run "$JACK" ubuntu port-test example.com 80
  [ "$status" -eq 0 ]
  [[ "$output" == *"example.com:80 open"* ]]
  logged "nc -z -w 3 example.com 80"
}

@test "port-test reports a closed port with exit 1" {
  stub_cmd nc 'exit 1'
  run "$JACK" ubuntu port-test example.com 80
  [ "$status" -eq 1 ]
  [[ "$output" == *"example.com:80 closed"* ]]
}

@test "port-test validates its arguments" {
  stub_cmd nc ''
  run "$JACK" ubuntu port-test example.com 99999
  [ "$status" -eq 2 ]
  run "$JACK" ubuntu port-test -x 80
  [ "$status" -eq 2 ]
  run "$JACK" ubuntu port-test example.com
  [ "$status" -eq 2 ]
  not_logged_like "^nc"
}

@test "count counts files recursively" {
  mkdir -p "$BATS_TEST_TMPDIR/d/sub"
  touch "$BATS_TEST_TMPDIR/d/a" "$BATS_TEST_TMPDIR/d/b" "$BATS_TEST_TMPDIR/d/sub/c"
  run "$JACK" ubuntu count "$BATS_TEST_TMPDIR/d"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "count rejects a missing directory" {
  run "$JACK" ubuntu count "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
}

@test "mysql-config shows the default options lines" {
  stub_cmd mysql "printf 'noise\nDefault options are read from the following files\n/etc/my.cnf /etc/mysql/my.cnf\n'"
  run "$JACK" ubuntu mysql-config
  [ "$status" -eq 0 ]
  [[ "$output" == *"/etc/my.cnf"* ]]
  logged "mysql --verbose --help"
}

@test "ssh-key uses the shared helper" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  stub_cmd ssh-keygen ''
  run "$JACK" ubuntu ssh-key me@example.com
  [ "$status" -eq 0 ]
  logged "ssh-keygen -t ed25519 -C me@example.com -f $HOME/.ssh/id_ed25519"
}
```

**Step 2: Run to verify failure**

Run: `bats tests/ubuntu.bats`
Expected: FAIL with "unknown theme: ubuntu".

**Step 3: Implement**

Create `lib/ubuntu.sh`:

```bash
JACK_DESC="Ubuntu chores"
JACK_DOC_flush_dns="Restart named and nscd to flush DNS caches, needs root"
JACK_DOC_ports="List listening TCP ports with owning processes"
JACK_DOC_port_test="Check whether a host accepts TCP connections on a port"
JACK_DOC_count="Count files under a directory"
JACK_DOC_mysql_config="Show where MySQL looks for option files"
JACK_DOC_ssh_key="Generate an ed25519 SSH key for an email"

ubuntu_flush_dns() {
  [ $# -eq 0 ] || die_usage "usage: jack ubuntu flush-dns"
  require_root ubuntu flush-dns
  require_cmd service
  service named restart
  service nscd restart
}

ubuntu_ports() {
  [ $# -eq 0 ] || die_usage "usage: jack ubuntu ports"
  require_cmd ss
  ss -lntp
}

ubuntu_port_test() {
  [ $# -eq 2 ] || die_usage "usage: jack ubuntu port-test <host> <port>"
  case "$1" in
    ''|-*|*[!A-Za-z0-9.:-]*) die_usage "invalid host: $1" ;;
  esac
  validate_port "$2"
  require_cmd nc
  if nc -z -w 3 "$1" "$2"; then
    echo "${GREEN}$1:$2 open${RESET}"
  else
    echo "${RED}$1:$2 closed${RESET}" >&2
    return 1
  fi
}

ubuntu_count() {
  [ $# -le 1 ] || die_usage "usage: jack ubuntu count [dir]"
  local dir="${1:-.}"
  [ -d "$dir" ] || die_usage "not a directory: $dir"
  find "$dir" -type f | wc -l | tr -d ' '
}

ubuntu_mysql_config() {
  [ $# -eq 0 ] || die_usage "usage: jack ubuntu mysql-config"
  require_cmd mysql
  mysql --verbose --help | grep -A 1 "Default options"
}

ubuntu_ssh_key() {
  ssh_keygen_for ubuntu "$@"
}
```

**Step 4: Run to verify pass, then commit**

Run: `bats tests/`
Expected: all PASS.

```bash
git add lib/ubuntu.sh tests/ubuntu.bats
git commit -m "feat: add ubuntu theme network and info actions"
```

---

### Task 13: ubuntu theme, files and mount

**Files:**
- Modify: `lib/ubuntu.sh`
- Modify: `tests/ubuntu.bats`

**Step 1: Write the failing tests**

Append to `tests/ubuntu.bats`:

```bash

make_sized_files() {
  BIG_DIR="$BATS_TEST_TMPDIR/big"
  mkdir -p "$BIG_DIR/sub"
  head -c 5000 /dev/zero > "$BIG_DIR/large"
  head -c 5000 /dev/zero > "$BIG_DIR/sub/large2"
  head -c 10 /dev/zero > "$BIG_DIR/small"
}

@test "big-files lists only files over the size" {
  make_sized_files
  run "$JACK" ubuntu big-files 1k "$BIG_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"large"* ]]
  [[ "$output" == *"large2"* ]]
  [[ "$output" != *"small"* ]]
}

@test "big-files with no matches exits 1" {
  make_sized_files
  run "$JACK" ubuntu big-files 1M "$BIG_DIR"
  [ "$status" -eq 1 ]
}

@test "big-files rejects a bad size" {
  make_sized_files
  run "$JACK" ubuntu big-files '1k;x' "$BIG_DIR"
  [ "$status" -eq 2 ]
  run "$JACK" ubuntu big-files k "$BIG_DIR"
  [ "$status" -eq 2 ]
}

@test "big-files-delete -y deletes the matches and keeps the rest" {
  make_sized_files
  run "$JACK" ubuntu big-files-delete 1k "$BIG_DIR" -y
  [ "$status" -eq 0 ]
  [ ! -e "$BIG_DIR/large" ]
  [ ! -e "$BIG_DIR/sub/large2" ]
  [ -e "$BIG_DIR/small" ]
}

@test "big-files-delete lists the count and aborts when declined" {
  make_sized_files
  run "$JACK" ubuntu big-files-delete 1k "$BIG_DIR" <<< "n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 file(s)"* ]]
  [ -e "$BIG_DIR/large" ]
}

@test "big-files-delete with no matches exits 1 without prompting" {
  make_sized_files
  run "$JACK" ubuntu big-files-delete 1M "$BIG_DIR" -y
  [ "$status" -eq 1 ]
}

@test "mount needs root" {
  mkdir -p "$BATS_TEST_TMPDIR/mnt"
  stub_cmd id 'echo 501'
  stub_cmd mount ''
  run "$JACK" ubuntu mount /dev/sdb1 "$BATS_TEST_TMPDIR/mnt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo jack ubuntu mount /dev/sdb1"* ]]
  not_logged_like "^mount"
}

@test "mount mounts the device as root" {
  mkdir -p "$BATS_TEST_TMPDIR/mnt"
  stub_cmd id 'echo 0'
  stub_cmd mount ''
  run "$JACK" ubuntu mount /dev/sdb1 "$BATS_TEST_TMPDIR/mnt"
  [ "$status" -eq 0 ]
  logged "mount /dev/sdb1 $BATS_TEST_TMPDIR/mnt"
}

@test "mount validates device and target before the root check" {
  stub_cmd id 'echo 501'
  stub_cmd mount ''
  run "$JACK" ubuntu mount sdb1 "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
  run "$JACK" ubuntu mount /dev/sdb1 "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
  run "$JACK" ubuntu mount /dev/sdb1
  [ "$status" -eq 2 ]
}
```

**Step 2: Run to verify failure**

Run: `bats tests/ubuntu.bats`
Expected: the new tests FAIL with "unknown action". The meta test also stays green because nothing is added yet.

**Step 3: Implement**

In `lib/ubuntu.sh`, add under the existing `JACK_DOC_` lines:

```bash
JACK_DOC_big_files="List files over a size such as 500k, 10M or 1G"
JACK_DOC_big_files_delete="Delete files over a size after showing how many match"
JACK_DOC_mount="Mount a device at a target directory, needs root"
```

Append to `lib/ubuntu.sh`:

```bash

_ubuntu_validate_size() {
  case "$1" in
    ''|*[!0-9kMGcb]*|*[kMGcb]?*|[kMGcb]*) die_usage "invalid size: $1" ;;
  esac
}

_ubuntu_big_matches() {
  find "$2" -type f -size +"$1"
}

ubuntu_big_files() {
  { [ $# -ge 1 ] && [ $# -le 2 ]; } || die_usage "usage: jack ubuntu big-files <size> [dir]"
  _ubuntu_validate_size "$1"
  local dir="${2:-.}" matches
  [ -d "$dir" ] || die_usage "not a directory: $dir"
  matches="$(_ubuntu_big_matches "$1" "$dir")"
  if [ -z "$matches" ]; then
    echo "no files over $1 in $dir" >&2
    return 1
  fi
  printf '%s\n' "$matches"
}

ubuntu_big_files_delete() {
  local usage="usage: jack ubuntu big-files-delete <size> [dir] [-y]"
  local assume_yes=0 n=$#
  while [ "$n" -gt 0 ]; do
    case "$1" in
      -y) assume_yes=1; shift ;;
      -*) die_usage "$usage" ;;
      *) set -- "$@" "$1"; shift ;;
    esac
    n=$((n - 1))
  done
  { [ $# -ge 1 ] && [ $# -le 2 ]; } || die_usage "$usage"
  _ubuntu_validate_size "$1"
  local dir="${2:-.}" matches count
  [ -d "$dir" ] || die_usage "not a directory: $dir"
  matches="$(_ubuntu_big_matches "$1" "$dir")"
  if [ -z "$matches" ]; then
    echo "no files over $1 in $dir" >&2
    return 1
  fi
  printf '%s\n' "$matches"
  count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
  confirm_unless_yes "Delete $count file(s) over $1 in $dir?" "$assume_yes" || return 1
  find "$dir" -type f -size +"$1" -delete
}

ubuntu_mount() {
  [ $# -eq 2 ] || die_usage "usage: jack ubuntu mount <device> <target>"
  case "$1" in
    /dev/?*) ;;
    *) die_usage "invalid device: $1" ;;
  esac
  [ -d "$2" ] || die_usage "not a directory: $2"
  require_root ubuntu mount "$@"
  require_cmd mount
  mount "$1" "$2"
}
```

**Step 4: Run to verify pass, then commit**

Run: `bats tests/`
Expected: all PASS.

```bash
git add lib/ubuntu.sh tests/ubuntu.bats
git commit -m "feat: add ubuntu file and mount actions"
```

---

### Task 14: README and end-to-end check

**Files:**
- Modify: `README.md`
- Modify: `tests/alias.bats`

**Step 1: Add an end-to-end alias test**

Append to `tests/alias.bats`:

```bash

@test "real themes expose their aliases" {
  run "$JACK" alias print
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias dstop='jack docker stop'"* ]]
  [[ "$output" == *"alias greset='jack git reset-remote'"* ]]
  [[ "$output" == *"alias npmcc='jack npm cache-clear'"* ]]
  [[ "$output" == *"alias mydump='jack mysql dump'"* ]]
}
```

**Step 2: Run to verify it passes**

Run: `bats tests/alias.bats`
Expected: PASS.

**Step 3: Update the README**

Replace the `## Use` and `## Add a theme` sections with:

````markdown
## Use

```bash
jack                    # list themes
jack port               # list actions with descriptions
jack port list [port]
jack port kill <port> [-y]
jack cheat list [theme] # every action with its description
jack alias print        # alias lines for aliased actions
```

Themes: `port`, `docker`, `git`, `npm`, `mysql`, `mac`, `ubuntu`, `cheat`, `alias`.

Action names use hyphens on the command line and underscores in code, so `jack mac flush-dns` runs `mac_flush_dns`. Destructive actions prompt and accept `-y`. Actions that need root exit with the `sudo jack ...` line to run, jack never calls sudo itself.

### Aliases

```bash
eval "$(jack alias print)"
```

Add that line to `.zshrc` or `.bashrc`.

## Add a theme

Create `lib/<theme>.sh` with a `JACK_DESC="..."` line and functions named `<theme>_<action>`. Prefix helpers with `_<theme>_`. Every action needs a `JACK_DOC_<action>="one line"` assignment, and may add `JACK_ALIAS_<action>="name"`. Values must not contain double quotes. Tests fail when a doc is missing or an alias repeats. Nothing else needs editing.
````

**Step 4: Full run and smoke test**

Run: `bats tests/`
Expected: all PASS.

Run: `bin/jack cheat list | head -40`
Expected: theme headers with hyphenated actions and descriptions, no `core`.

Run: `eval "$(bin/jack alias print)" && alias dstop`
Expected: `alias dstop='jack docker stop'` or `dstop='jack docker stop'` depending on the shell.

**Step 5: Commit**

```bash
git add README.md tests/alias.bats
git commit -m "docs: document new themes, cheat and alias"
```
