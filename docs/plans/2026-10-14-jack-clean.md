# jack clean Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a `clean` theme so `jack clean <target>` runs the cleanup remedies suggested by the server-monitoring disk checkers.

**Architecture:** One new file, `lib/clean.sh`, with one function per remedy plus `list` and `all`. `npm` and `docker` delegate to the existing `npm_cache_clear` and `docker_prune` by sourcing those theme files. Helpers are prefixed `_clean_` so action discovery ignores them. Design: `docs/plans/2026-10-14-jack-clean-design.md`.

**Tech Stack:** bash, bats-core. Stub commands on `PATH` via `tests/test_helper.bash`.

**Conventions to follow** (all from `lib/core.sh`):
- Every public function `clean_<action>` needs `JACK_DOC_<action>="..."` and `JACK_USAGE_<action>="..."` lines at the top of the file. No double quotes inside values. `tests/meta.bats` fails otherwise.
- Bad args: `die_usage "usage: $(jack_usage clean <action>)"`. Missing tool: `require_cmd`. Root: `require_root clean <action>`. Prompts: `parse_yes_only` then `confirm_unless_yes "..." "$ASSUME_YES"`.
- OS checks read `${JACK_UNAME:-$(uname -s)}` so tests can override with `export JACK_UNAME=Darwin`.
- Code comments only for non-obvious constraints. No banner comments.
- The working tree has unrelated uncommitted changes. Always `git add` specific files, never `git add -A`.

---

### Task 1: Theme skeleton and simple cache actions

**Files:**
- Create: `lib/clean.sh`
- Create: `tests/clean.bats`

**Step 1: Write the failing tests**

Create `tests/clean.bats`:

```bash
#!/usr/bin/env bats

load test_helper

setup() {
  setup_stubs
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

isolate_path() {
  local bin="$BATS_TEST_TMPDIR/bin" tool src
  mkdir -p "$bin"
  for tool in bash env sed tr head wc awk id find rm mkdir chmod touch basename dirname cat uname readlink grep sort; do
    src="$(command -v "$tool")"
    case "$src" in
      /*) ln -sf "$src" "$bin/$tool" ;;
    esac
  done
  PATH="$STUB_DIR:$bin"
}

@test "simple actions run their command" {
  local row act cmd
  for row in "pip|pip cache purge" "yarn|yarn cache clean" "pnpm|pnpm store prune" "composer|composer clear-cache" "go|go clean -modcache"; do
    act="${row%%|*}"
    cmd="${row#*|}"
    stub_cmd "${cmd%% *}" ''
    run "$JACK" clean "$act"
    [ "$status" -eq 0 ] || { echo "$act failed: $output"; return 1; }
    logged "$cmd" || { echo "$act did not run: $cmd"; return 1; }
  done
}

@test "simple actions fail when the tool is missing" {
  local act
  isolate_path
  for act in pip yarn pnpm composer go; do
    run "$JACK" clean "$act"
    [ "$status" -eq 1 ] || { echo "$act status $status"; return 1; }
    [[ "$output" == *"missing command: $act"* ]] || { echo "$act: $output"; return 1; }
  done
}

@test "simple actions reject extra arguments" {
  stub_cmd pip ''
  run "$JACK" clean pip extra
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: jack clean pip"* ]]
  not_logged_like "^pip"
}
```

**Step 2: Run to verify failure**

Run: `bats tests/clean.bats`
Expected: FAIL, output contains `unknown theme: clean`.

**Step 3: Write the implementation**

Create `lib/clean.sh`:

```bash
JACK_DESC="Cache and disk cleanup"
JACK_DOC_pip="Purge the pip cache"
JACK_DOC_yarn="Clean the Yarn cache"
JACK_DOC_pnpm="Prune the pnpm store"
JACK_DOC_composer="Clear the Composer cache"
JACK_DOC_go="Clean the Go module cache"
JACK_USAGE_pip=""
JACK_USAGE_yarn=""
JACK_USAGE_pnpm=""
JACK_USAGE_composer=""
JACK_USAGE_go=""

_clean_simple() {
  local action="$1" extra="$2"
  shift 2
  [ "$extra" -eq 0 ] || die_usage "usage: $(jack_usage clean "$action")"
  require_cmd "$1"
  "$@"
}

clean_pip() { _clean_simple pip $# pip cache purge; }
clean_yarn() { _clean_simple yarn $# yarn cache clean; }
clean_pnpm() { _clean_simple pnpm $# pnpm store prune; }
clean_composer() { _clean_simple composer $# composer clear-cache; }
clean_go() { _clean_simple go $# go clean -modcache; }
```

**Step 4: Run to verify pass**

Run: `bats tests/clean.bats`
Expected: 3 tests pass.

**Step 5: Commit**

```bash
git add lib/clean.sh tests/clean.bats
git commit -m "feat: add clean theme with pip, yarn, pnpm, composer and go

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: npm and docker delegates

**Files:**
- Modify: `lib/clean.sh`
- Modify: `tests/clean.bats`

**Step 1: Write the failing tests**

Append to `tests/clean.bats`:

```bash
@test "npm delegates to npm cache-clear" {
  stub_cmd npm ''
  run "$JACK" clean npm
  [ "$status" -eq 0 ]
  logged "npm cache clear --force"
}

@test "npm rejects extra arguments" {
  stub_cmd npm ''
  run "$JACK" clean npm extra
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: jack clean npm"* ]]
}

@test "docker prunes with -y" {
  stub_cmd docker ''
  run "$JACK" clean docker -y
  [ "$status" -eq 0 ]
  logged "docker system prune -f"
}

@test "docker aborts when declined" {
  stub_cmd docker ''
  run "$JACK" clean docker <<< "n"
  [ "$status" -eq 1 ]
  not_logged_like "^docker"
}

@test "docker rejects unknown flags" {
  stub_cmd docker ''
  run "$JACK" clean docker --volumes
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: jack clean docker"* ]]
}
```

**Step 2: Run to verify failure**

Run: `bats tests/clean.bats`
Expected: the 5 new tests FAIL with `unknown action: clean npm` or `clean docker`.

**Step 3: Write the implementation**

At the very top of `lib/clean.sh`, before `JACK_DESC`, nothing changes. Add the metadata lines below to the metadata block:

```bash
JACK_DOC_npm="Force-clear the npm cache"
JACK_DOC_docker="Remove unused Docker containers, networks, images and cache"
JACK_USAGE_npm=""
JACK_USAGE_docker="[-y]"
```

Add after the metadata block and before `_clean_simple`:

```bash
. "$JACK_ROOT/lib/npm.sh"
. "$JACK_ROOT/lib/docker.sh"
```

Append the functions:

```bash
clean_npm() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage clean npm)"
  npm_cache_clear
}

clean_docker() {
  parse_yes_only "$(jack_usage clean docker)" "$@"
  if [ "$ASSUME_YES" -eq 1 ]; then
    docker_prune -y
  else
    docker_prune
  fi
}
```

**Step 4: Run to verify pass**

Run: `bats tests/clean.bats`
Expected: all tests pass.

**Step 5: Commit**

```bash
git add lib/clean.sh tests/clean.bats
git commit -m "feat: add clean npm and docker delegates

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: OS-specific actions (brew, xcode, apt, journal, snap)

**Files:**
- Modify: `lib/clean.sh`
- Modify: `tests/clean.bats`

**Step 1: Write the failing tests**

Append to `tests/clean.bats`:

```bash
@test "brew cleans on macOS" {
  export JACK_UNAME=Darwin
  stub_cmd brew ''
  run "$JACK" clean brew
  [ "$status" -eq 0 ]
  logged "brew cleanup --prune=all"
}

@test "brew refuses on Linux" {
  export JACK_UNAME=Linux
  stub_cmd brew ''
  run "$JACK" clean brew
  [ "$status" -eq 1 ]
  [[ "$output" == *"brew is for macOS only"* ]]
  not_logged_like "^brew"
}

@test "xcode deletes DerivedData with -y" {
  export JACK_UNAME=Darwin
  mkdir -p "$HOME/Library/Developer/Xcode/DerivedData/App"
  run "$JACK" clean xcode -y
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/Library/Developer/Xcode/DerivedData" ]
}

@test "xcode keeps DerivedData when declined" {
  export JACK_UNAME=Darwin
  mkdir -p "$HOME/Library/Developer/Xcode/DerivedData/App"
  run "$JACK" clean xcode <<< "n"
  [ "$status" -eq 1 ]
  [ -d "$HOME/Library/Developer/Xcode/DerivedData/App" ]
}

@test "xcode with no DerivedData has nothing to remove" {
  export JACK_UNAME=Darwin
  run "$JACK" clean xcode -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to remove"* ]]
}

@test "xcode refuses on Linux" {
  export JACK_UNAME=Linux
  run "$JACK" clean xcode -y
  [ "$status" -eq 1 ]
  [[ "$output" == *"xcode is for macOS only"* ]]
}

@test "apt needs root" {
  export JACK_UNAME=Linux
  stub_cmd id 'echo 501'
  stub_cmd apt ''
  run "$JACK" clean apt
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo jack clean apt"* ]]
  not_logged_like "^apt"
}

@test "apt cleans as root" {
  export JACK_UNAME=Linux
  stub_cmd id 'echo 0'
  stub_cmd apt ''
  run "$JACK" clean apt
  [ "$status" -eq 0 ]
  logged "apt clean"
}

@test "apt refuses on macOS" {
  export JACK_UNAME=Darwin
  stub_cmd id 'echo 0'
  stub_cmd apt ''
  run "$JACK" clean apt
  [ "$status" -eq 1 ]
  [[ "$output" == *"apt is for Linux only"* ]]
}

@test "journal needs root" {
  export JACK_UNAME=Linux
  stub_cmd id 'echo 501'
  stub_cmd journalctl ''
  run "$JACK" clean journal
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo jack clean journal"* ]]
}

@test "journal vacuums to 100M as root" {
  export JACK_UNAME=Linux
  stub_cmd id 'echo 0'
  stub_cmd journalctl ''
  run "$JACK" clean journal
  [ "$status" -eq 0 ]
  logged "journalctl --vacuum-size=100M"
}

snap_stub() {
  stub_cmd snap 'if [ "$1" = list ]; then
  printf "Name Version Rev Tracking Publisher Notes\ncore20 1 1 latest canonical disabled\ncore20 1 2 latest canonical -\n"
fi'
}

@test "snap removes only disabled revisions with -y" {
  export JACK_UNAME=Linux
  stub_cmd id 'echo 0'
  snap_stub
  run "$JACK" clean snap -y
  [ "$status" -eq 0 ]
  logged "snap remove core20 --revision=1"
  not_logged_like "revision=2"
}

@test "snap aborts when declined" {
  export JACK_UNAME=Linux
  stub_cmd id 'echo 0'
  snap_stub
  run "$JACK" clean snap <<< "n"
  [ "$status" -eq 1 ]
  not_logged_like "^snap remove"
}

@test "snap needs root" {
  export JACK_UNAME=Linux
  stub_cmd id 'echo 501'
  snap_stub
  run "$JACK" clean snap -y
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo jack clean snap"* ]]
}

@test "snap keeps an active snap whose name contains disabled" {
  export JACK_UNAME=Linux
  stub_cmd id 'echo 0'
  stub_cmd snap 'if [ "$1" = list ]; then
  printf "Name Version Rev Tracking Publisher Notes\ndisabled-tool 1 5 latest pub -\ncore20 1 1 latest canonical disabled\n"
fi'
  run "$JACK" clean snap -y
  [ "$status" -eq 0 ]
  logged "snap remove core20 --revision=1"
  not_logged_like "disabled-tool"
}

@test "snap exits non-zero when a remove fails and keeps going" {
  export JACK_UNAME=Linux
  stub_cmd id 'echo 0'
  stub_cmd snap 'if [ "$1" = list ]; then
  printf "Name Version Rev Tracking Publisher Notes\ncore20 1 1 latest canonical disabled\nlxd 1 2 latest canonical disabled\n"
elif [ "$1" = remove ] && [ "$2" = core20 ]; then
  exit 1
fi'
  run "$JACK" clean snap -y
  [ "$status" -eq 1 ]
  logged "snap remove lxd --revision=2"
}

@test "snap fails when snap list fails" {
  export JACK_UNAME=Linux
  stub_cmd id 'echo 0'
  stub_cmd snap 'exit 1'
  run "$JACK" clean snap -y
  [ "$status" -eq 1 ]
  [[ "$output" == *"snap list failed"* ]] || false
  not_logged_like "^snap remove"
}

@test "snap with no disabled revisions has nothing to remove" {
  export JACK_UNAME=Linux
  stub_cmd id 'echo 0'
  stub_cmd snap ''
  run "$JACK" clean snap -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to remove"* ]]
}
```

**Step 2: Run to verify failure**

Run: `bats tests/clean.bats`
Expected: the new tests FAIL with `unknown action`.

**Step 3: Write the implementation**

Add to the metadata block:

```bash
JACK_DOC_brew="Remove all Homebrew cache, macOS only"
JACK_DOC_xcode="Delete Xcode DerivedData, macOS only"
JACK_DOC_apt="Clear the APT package cache, Linux, needs root"
JACK_DOC_journal="Trim systemd journal logs to 100M, Linux, needs root"
JACK_DOC_snap="Remove disabled snap revisions, Linux, needs root"
JACK_USAGE_brew=""
JACK_USAGE_xcode="[-y]"
JACK_USAGE_apt=""
JACK_USAGE_journal=""
JACK_USAGE_snap="[-y]"
```

Add the helper after `_clean_simple`:

```bash
_clean_require_os() {
  [ "${JACK_UNAME:-$(uname -s)}" = "$1" ] || die "$3 is for $2 only"
}
```

Append the functions:

```bash
clean_brew() {
  _clean_require_os Darwin macOS brew
  _clean_simple brew $# brew cleanup --prune=all
}

clean_xcode() {
  _clean_require_os Darwin macOS xcode
  parse_yes_only "$(jack_usage clean xcode)" "$@"
  local dir="${HOME:?}/Library/Developer/Xcode/DerivedData"
  if [ ! -d "$dir" ]; then
    echo "nothing to remove"
    return 0
  fi
  confirm_unless_yes "Delete $dir?" "$ASSUME_YES" || return 1
  rm -rf -- "$dir"
}

clean_apt() {
  _clean_require_os Linux Linux apt
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage clean apt)"
  require_root clean apt
  _clean_simple apt 0 apt clean
}

clean_journal() {
  _clean_require_os Linux Linux journal
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage clean journal)"
  require_root clean journal
  _clean_simple journal 0 journalctl --vacuum-size=100M
}

clean_snap() {
  _clean_require_os Linux Linux snap
  parse_yes_only "$(jack_usage clean snap)" "$@"
  require_root clean snap
  require_cmd snap
  local listing revs count name rev failed=0
  listing="$(snap list --all)" || die "snap list failed"
  revs="$(printf '%s\n' "$listing" | awk '$NF ~ /(^|,)disabled(,|$)/ {print $1, $3}')"
  if [ -z "$revs" ]; then
    echo "nothing to remove"
    return 0
  fi
  count="$(printf '%s\n' "$revs" | wc -l | tr -d ' ')"
  confirm_unless_yes "Remove $count old snap revision(s)?" "$ASSUME_YES" || return 1
  while read -r name rev; do
    snap remove "$name" --revision="$rev" || failed=1
  done <<< "$revs"
  return "$failed"
}
```

**Step 4: Run to verify pass**

Run: `bats tests/clean.bats`
Expected: all tests pass.

**Step 5: Commit**

```bash
git add lib/clean.sh tests/clean.bats
git commit -m "feat: add clean brew, xcode, apt, journal and snap

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: gradle, maven, cargo

**Files:**
- Modify: `lib/clean.sh`
- Modify: `tests/clean.bats`

Two choices differ from the upstream advice text and are worth a line in the commit body. Gradle removes the whole `~/.gradle/caches`, since "old version" dirs can't be told apart safely, and Gradle rebuilds it. Maven deletes SNAPSHOT directories older than 90 days that hold no recently modified file, using `find`, since `dependency:purge-local-repository` only works inside a project.

**Step 1: Write the failing tests**

Append to `tests/clean.bats`:

```bash
@test "gradle stops the daemon and deletes caches with -y" {
  stub_cmd gradle ''
  mkdir -p "$HOME/.gradle/caches/8.0"
  run "$JACK" clean gradle -y
  [ "$status" -eq 0 ]
  logged "gradle --stop"
  [ ! -e "$HOME/.gradle/caches" ]
}

@test "gradle keeps caches when declined" {
  stub_cmd gradle ''
  mkdir -p "$HOME/.gradle/caches/8.0"
  run "$JACK" clean gradle <<< "n"
  [ "$status" -eq 1 ]
  [ -d "$HOME/.gradle/caches/8.0" ]
  not_logged_like "^gradle"
}

@test "maven deletes only old SNAPSHOT artifacts" {
  local repo="$HOME/.m2/repository"
  mkdir -p "$repo/a/1.0-SNAPSHOT" "$repo/b/2.0-SNAPSHOT" "$repo/c/3.0"
  touch -t 202001010000 "$repo/a/1.0-SNAPSHOT/a.jar"
  touch -t 202001010000 "$repo/a/1.0-SNAPSHOT"
  run "$JACK" clean maven -y
  [ "$status" -eq 0 ]
  [ ! -e "$repo/a/1.0-SNAPSHOT" ]
  [ -d "$repo/b/2.0-SNAPSHOT" ]
  [ -d "$repo/c/3.0" ]
}

@test "maven keeps an old SNAPSHOT dir that has a recent file" {
  local repo="$HOME/.m2/repository"
  mkdir -p "$repo/a/1.0-SNAPSHOT"
  touch "$repo/a/1.0-SNAPSHOT/a.jar"
  touch -t 202001010000 "$repo/a/1.0-SNAPSHOT"
  run "$JACK" clean maven -y
  [ "$status" -eq 0 ]
  [ -f "$repo/a/1.0-SNAPSHOT/a.jar" ]
}

@test "maven ignores a SNAPSHOT file that is not a directory" {
  local repo="$HOME/.m2/repository"
  mkdir -p "$repo/a"
  touch -t 202001010000 "$repo/a/x-SNAPSHOT"
  run "$JACK" clean maven -y
  [ "$status" -eq 0 ]
  [ -f "$repo/a/x-SNAPSHOT" ]
}

@test "maven handles directory names with spaces" {
  local repo="$HOME/.m2/repository"
  mkdir -p "$repo/my lib/1.0-SNAPSHOT"
  touch -t 202001010000 "$repo/my lib/1.0-SNAPSHOT/a.jar"
  touch -t 202001010000 "$repo/my lib/1.0-SNAPSHOT"
  run "$JACK" clean maven -y
  [ "$status" -eq 0 ]
  [ ! -e "$repo/my lib/1.0-SNAPSHOT" ]
  [ -d "$repo/my lib" ]
}

@test "maven with nothing old has nothing to remove" {
  mkdir -p "$HOME/.m2/repository/b/2.0-SNAPSHOT"
  run "$JACK" clean maven -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to remove"* ]]
}

@test "cargo autocleans when cargo-cache is present" {
  stub_cmd cargo ''
  run "$JACK" clean cargo -y
  [ "$status" -eq 0 ]
  logged "cargo cache --autoclean"
  not_logged_like "cargo install"
}

@test "cargo installs cargo-cache first when missing" {
  stub_cmd cargo '[ "$1 $2" = "cache --version" ] && exit 1; exit 0'
  run "$JACK" clean cargo -y
  [ "$status" -eq 0 ]
  logged "cargo install cargo-cache"
  logged "cargo cache --autoclean"
}

@test "cargo aborts when declined" {
  stub_cmd cargo ''
  run "$JACK" clean cargo <<< "n"
  [ "$status" -eq 1 ]
  not_logged_like "^cargo"
}
```

**Step 2: Run to verify failure**

Run: `bats tests/clean.bats`
Expected: the 7 new tests FAIL with `unknown action`.

**Step 3: Write the implementation**

Add to the metadata block:

```bash
JACK_DOC_gradle="Stop the Gradle daemon and delete ~/.gradle/caches"
JACK_DOC_maven="Delete Maven SNAPSHOT artifacts older than 90 days"
JACK_DOC_cargo="Autoclean the cargo cache, installs cargo-cache if missing"
JACK_USAGE_gradle="[-y]"
JACK_USAGE_maven="[-y]"
JACK_USAGE_cargo="[-y]"
```

Append the functions:

```bash
clean_gradle() {
  parse_yes_only "$(jack_usage clean gradle)" "$@"
  require_cmd gradle
  local dir="${HOME:?}/.gradle/caches"
  confirm_unless_yes "Stop the Gradle daemon and delete $dir?" "$ASSUME_YES" || return 1
  gradle --stop
  rm -rf -- "$dir"
}

clean_maven() {
  parse_yes_only "$(jack_usage clean maven)" "$@"
  local repo="${HOME:?}/.m2/repository" dir old=()
  if [ ! -d "$repo" ]; then
    echo "nothing to remove"
    return 0
  fi
  while IFS= read -r -d '' dir; do
    if [ -z "$(find "$dir" -type f -mtime -90 -print -quit)" ]; then
      old+=("$dir")
    fi
  done < <(find "$repo" -type d -name '*-SNAPSHOT' -mtime +90 -prune -print0)
  if [ "${#old[@]}" -eq 0 ]; then
    echo "nothing to remove"
    return 0
  fi
  confirm_unless_yes "Delete ${#old[@]} SNAPSHOT artifact(s) older than 90 days?" "$ASSUME_YES" || return 1
  for dir in "${old[@]}"; do
    rm -rf -- "$dir"
  done
}

clean_cargo() {
  parse_yes_only "$(jack_usage clean cargo)" "$@"
  require_cmd cargo
  confirm_unless_yes "Autoclean the cargo cache, installing cargo-cache if missing?" "$ASSUME_YES" || return 1
  cargo cache --version >/dev/null 2>&1 || cargo install cargo-cache || die "cargo install failed"
  cargo cache --autoclean
}
```

**Step 4: Run to verify pass**

Run: `bats tests/clean.bats`
Expected: all tests pass.

**Step 5: Commit**

```bash
git add lib/clean.sh tests/clean.bats
git commit -m "feat: add clean gradle, maven and cargo

Gradle removes the whole caches dir and maven prunes old SNAPSHOTs,
since the upstream advice for both can't be run safely as written.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: `list` and the availability helper

**Files:**
- Modify: `lib/clean.sh`
- Modify: `tests/clean.bats`

**Step 1: Write the failing tests**

Append to `tests/clean.bats`:

```bash
@test "list shows installed state for every action" {
  export JACK_UNAME=Darwin
  isolate_path
  stub_cmd pip ''
  run "$JACK" clean list
  [ "$status" -eq 0 ]
  [[ "$output" =~ pip[[:space:]]+yes ]]
  [[ "$output" =~ pnpm[[:space:]]+no ]]
  [[ "$output" =~ apt[[:space:]]+no ]]
}

@test "list marks xcode available when DerivedData exists" {
  export JACK_UNAME=Darwin
  mkdir -p "$HOME/Library/Developer/Xcode/DerivedData"
  run "$JACK" clean list
  [[ "$output" =~ xcode[[:space:]]+yes ]]
}

@test "list does not list itself or all" {
  run "$JACK" clean list
  if grep -qE '^(list|all)[[:space:]]' <<< "$output"; then false; fi
}

@test "list rejects arguments" {
  run "$JACK" clean list extra
  [[ "$output" == *"usage: jack clean list"* ]] || false
  [ "$status" -eq 2 ]
}
```

**Step 2: Run to verify failure**

Run: `bats tests/clean.bats`
Expected: the new tests FAIL with `unknown action: clean list`.

**Step 3: Write the implementation**

Add to the metadata block:

```bash
JACK_DOC_list="Show every clean action and whether it can run on this machine"
JACK_USAGE_list=""
```

Add after `_clean_require_os`:

```bash
_clean_available() {
  local os="${JACK_UNAME:-$(uname -s)}"
  case "$1" in
    xcode) [ "$os" = Darwin ] && [ -d "${HOME:?}/Library/Developer/Xcode/DerivedData" ] ;;
    maven) [ -d "${HOME:?}/.m2/repository" ] ;;
    brew) [ "$os" = Darwin ] && command -v brew >/dev/null 2>&1 ;;
    apt|snap) [ "$os" = Linux ] && command -v "$1" >/dev/null 2>&1 ;;
    journal) [ "$os" = Linux ] && command -v journalctl >/dev/null 2>&1 ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}
```

Append:

```bash
clean_list() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage clean list)"
  local act ok
  for act in $(jack_actions clean); do
    case "$act" in list|all) continue ;; esac
    if _clean_available "$act"; then ok=yes; else ok=no; fi
    printf '%-10s %-4s %s\n' "$act" "$ok" "$(jack_meta clean DOC "$act")"
  done
}
```

**Step 4: Run to verify pass**

Run: `bats tests/clean.bats`
Expected: all tests pass.

**Step 5: Commit**

```bash
git add lib/clean.sh tests/clean.bats
git commit -m "feat: add clean list

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: `all`

**Files:**
- Modify: `lib/clean.sh`
- Modify: `tests/clean.bats`

**Step 1: Write the failing tests**

Append to `tests/clean.bats`:

```bash
@test "all runs available actions and skips the rest" {
  export JACK_UNAME=Darwin
  isolate_path
  stub_cmd pip ''
  stub_cmd npm ''
  stub_cmd docker ''
  run "$JACK" clean all -y
  [ "$status" -eq 0 ]
  logged "pip cache purge"
  logged "npm cache clear --force"
  logged "docker system prune -f"
  [[ "$output" == *"skip pnpm, not available"* ]]
}

@test "all never runs gradle, maven or cargo" {
  export JACK_UNAME=Darwin
  isolate_path
  stub_cmd gradle ''
  stub_cmd cargo ''
  mkdir -p "$HOME/.m2/repository/a/1.0-SNAPSHOT"
  touch -t 202001010000 "$HOME/.m2/repository/a/1.0-SNAPSHOT/a.jar"
  touch -t 202001010000 "$HOME/.m2/repository/a/1.0-SNAPSHOT"
  stub_cmd pip ''
  run "$JACK" clean all -y
  [ "$status" -eq 0 ]
  not_logged_like "^gradle"
  not_logged_like "^cargo"
  [ -d "$HOME/.m2/repository/a/1.0-SNAPSHOT" ]
}

@test "all skips root actions when not root and prints the sudo line" {
  export JACK_UNAME=Linux
  isolate_path
  stub_cmd id 'echo 501'
  stub_cmd apt ''
  run "$JACK" clean all -y
  [[ "$output" == *"skip apt, needs root: sudo jack clean apt"* ]]
  not_logged_like "^apt"
}

@test "all runs root actions as root" {
  export JACK_UNAME=Linux
  isolate_path
  stub_cmd id 'echo 0'
  stub_cmd apt ''
  run "$JACK" clean all -y
  [ "$status" -eq 0 ]
  logged "apt clean"
}

@test "all asks once and aborts when declined" {
  export JACK_UNAME=Darwin
  isolate_path
  stub_cmd pip ''
  stub_cmd npm ''
  run "$JACK" clean all <<< "n"
  [ "$status" -eq 1 ]
  not_logged_like "^pip"
  not_logged_like "^npm"
}

@test "all runs everything after one yes" {
  export JACK_UNAME=Darwin
  isolate_path
  stub_cmd pip ''
  stub_cmd npm ''
  run "$JACK" clean all <<< "y"
  [ "$status" -eq 0 ]
  logged "pip cache purge"
  logged "npm cache clear --force"
}

@test "all keeps going after a failure and exits non-zero" {
  export JACK_UNAME=Darwin
  isolate_path
  stub_cmd pip 'exit 1'
  stub_cmd npm ''
  run "$JACK" clean all -y
  [ "$status" -eq 1 ]
  logged "npm cache clear --force"
  [[ "$output" == *"failed: pip"* ]]
}

@test "all with nothing available says so" {
  export JACK_UNAME=Darwin
  isolate_path
  run "$JACK" clean all -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to clean"* ]]
}
```

The `isolate_path` helper from Task 1 limits `PATH` to the stubs and symlinks for the few utilities jack needs, so no real tool can leak in. If a test fails with `command not found`, add that utility to the helper list.

**Step 2: Run to verify failure**

Run: `bats tests/clean.bats`
Expected: the 8 new tests FAIL with `unknown action: clean all`.

**Step 3: Write the implementation**

Add to the metadata block:

```bash
JACK_DOC_all="Run every available clean action except gradle, maven and cargo"
JACK_USAGE_all="[-y]"
```

Add after `_clean_available`:

```bash
_clean_needs_root() {
  case "$1" in
    apt|journal|snap) return 0 ;;
  esac
  return 1
}
```

Append:

```bash
clean_all() {
  parse_yes_only "$(jack_usage clean all)" "$@"
  local act todo="" args failed=""
  for act in $(jack_actions clean); do
    case "$act" in list|all|gradle|maven|cargo) continue ;; esac
    if ! _clean_available "$act"; then
      echo "skip $act, not available"
      continue
    fi
    if _clean_needs_root "$act" && [ "$(id -u)" -ne 0 ]; then
      echo "skip $act, needs root: sudo jack clean $act"
      continue
    fi
    todo="$todo $act"
  done
  if [ -z "$todo" ]; then
    echo "nothing to clean"
    return 0
  fi
  confirm_unless_yes "Run:$todo?" "$ASSUME_YES" || return 1
  for act in $todo; do
    echo "==> $act"
    args=""
    case "$act" in xcode|snap|docker) args="-y" ;; esac
    ( "clean_$act" $args ) || failed="$failed $act"
  done
  if [ -n "$failed" ]; then
    echo "failed:$failed" >&2
    return 1
  fi
}
```

The subshell around each action stops a `die` in one action from killing the whole run.

**Step 4: Run to verify pass**

Run: `bats tests/clean.bats`
Expected: all tests pass.

**Step 5: Commit**

```bash
git add lib/clean.sh tests/clean.bats
git commit -m "feat: add clean all

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: README and full verification

**Files:**
- Modify: `README.md`

**Step 1: Update the README**

In the `## Use` code block, add after the `jack port kill <port> [-y]` line:

```bash
jack clean list         # which cleanups can run on this machine
jack clean pip          # purge one cache
jack clean all [-y]     # run every available cleanup
```

Change the themes line to:

```
Themes: `port`, `docker`, `git`, `npm`, `mysql`, `mac`, `ubuntu`, `clean`, `cheat`, `alias`, `completion`.
```

Add a short section after `### Completion`:

```markdown
### Clean

`jack clean` mirrors the remedies suggested by the disk checkers in [server-monitoring](https://github.com/ikidnapmyself/server-monitoring/tree/main/apps/checkers/checkers/disk). `jack clean all` skips gradle, maven and cargo, and prints the `sudo jack clean ...` line for actions that need root.
```

**Step 2: Run the whole suite**

Run: `bats tests/`
Expected: all tests pass, including `meta.bats` doc and usage checks for every new action. The suite had 140 passing tests before this plan.

**Step 3: Smoke test the real binary**

Run: `bin/jack clean list`
Expected: one line per action with `yes` or `no`, no errors.

Run: `bin/jack clean pip -h`
Expected: the doc line and `usage: jack clean pip`.

Run: `bin/jack __complete clean ''`
Expected: action names, including `list` and `all`.

**Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document jack clean

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
