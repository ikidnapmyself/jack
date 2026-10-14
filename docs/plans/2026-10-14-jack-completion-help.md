# jack completion and help Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add zsh and bash tab completion plus `help`/`-h` at every level, with usage text stored once as metadata.

**Architecture:** Each action declares `JACK_USAGE_<action>` next to its `JACK_DOC`. A `jack_usage` helper in `lib/core.sh` renders it, and every inline `usage:` string calls it. The dispatcher intercepts help words and a hidden `__complete` command. A new `completion` theme with actions `zsh` and `bash` prints the shell scripts, which call `jack __complete` at tab time.

**Tech Stack:** bash 3.2 compatible shell, bats, zsh for syntax checks.

Design: `docs/plans/2026-10-14-jack-completion-help-design.md`.

One deviation from the design: `jack completion zsh` is theme `completion` with actions `zsh` and `bash`, not one action taking an argument. The dispatcher needs a theme and an action, and an unknown shell then fails with the existing `unknown action` exit 2.

Run all tests with `bats tests/`. Baseline must be green before starting.

---

### Task 1: JACK_USAGE metadata and jack_usage helper

**Files:**
- Modify: `lib/core.sh` (after `jack_meta`)
- Modify: `lib/alias.sh`, `lib/cheat.sh`, `lib/docker.sh`, `lib/git.sh`, `lib/mac.sh`, `lib/mysql.sh`, `lib/npm.sh`, `lib/port.sh`, `lib/ubuntu.sh` (header block)
- Test: `tests/core.bats`, `tests/meta.bats`

**Step 1: Write the failing tests**

Append to `tests/core.bats`:

```bash
@test "jack_usage renders theme, hyphenated action and args" {
  run jack_usage port kill
  [ "$output" = "jack port kill <port> [-y]" ]
}

@test "jack_usage accepts underscores and drops the space for no-arg actions" {
  run jack_usage git remote_url
  [ "$output" = "jack git remote-url" ]
}
```

Append to `tests/meta.bats`:

```bash
@test "every public action has a JACK_USAGE" {
  local theme act missing=""
  for theme in $(jack_themes); do
    for act in $(jack_actions "$theme"); do
      grep -q "^JACK_USAGE_$act=\".*\"\$" "$JACK_ROOT/lib/$theme.sh" || missing="$missing $theme/$act"
    done
  done
  [ -z "$missing" ] || { echo "missing JACK_USAGE:$missing"; return 1; }
}
```

The grep checks presence, so an empty value for a no-arg action is valid.

**Step 2: Run to verify failure**

Run: `bats tests/core.bats tests/meta.bats`
Expected: the three new tests FAIL (`jack_usage: command not found`, `missing JACK_USAGE: ...`).

**Step 3: Add the helper**

In `lib/core.sh`, after `jack_meta`:

```bash
jack_usage() {
  local theme="$1" args
  args="$(jack_meta "$theme" USAGE "$(printf %s "$2" | tr - _)")"
  printf 'jack %s %s%s\n' "$theme" "$(printf %s "$2" | tr _ -)" "${args:+ $args}"
}
```

**Step 4: Add metadata to every theme**

Insert these lines in each file's header block, directly after the last existing `JACK_DOC_`/`JACK_ALIAS_` line and before the first function. Empty string means no arguments.

`lib/alias.sh`:
```bash
JACK_USAGE_print=""
```

`lib/cheat.sh`:
```bash
JACK_USAGE_list="[theme]"
```

`lib/docker.sh`:
```bash
JACK_USAGE_stop="[-y]"
JACK_USAGE_rm="[-y]"
JACK_USAGE_prune="[--volumes] [-y]"
JACK_USAGE_ps=""
JACK_USAGE_restart="<service>"
```

`lib/git.sh`:
```bash
JACK_USAGE_reset_remote="[-y]"
JACK_USAGE_remote_url=""
JACK_USAGE_submodules=""
```

`lib/mac.sh`:
```bash
JACK_USAGE_flush_dns=""
JACK_USAGE_nginx_reload=""
JACK_USAGE_ssh_key="<email>"
```

`lib/mysql.sh`:
```bash
JACK_USAGE_dump="<db> <file> [table...] [-u user]"
```

`lib/npm.sh`:
```bash
JACK_USAGE_cache_clear=""
JACK_USAGE_global_setup="[-y]"
```

`lib/port.sh`:
```bash
JACK_USAGE_list="[port]"
JACK_USAGE_kill="<port> [-y]"
```

`lib/ubuntu.sh`:
```bash
JACK_USAGE_flush_dns=""
JACK_USAGE_ports=""
JACK_USAGE_port_test="<host> <port>"
JACK_USAGE_count="[dir]"
JACK_USAGE_mysql_config=""
JACK_USAGE_ssh_key="<email>"
JACK_USAGE_big_files="<size> [dir]"
JACK_USAGE_big_files_delete="<size> [dir] [-y]"
JACK_USAGE_mount="<device> <target>"
```

**Step 5: Run to verify pass**

Run: `bats tests/`
Expected: all PASS.

**Step 6: Commit**

```bash
git add lib tests
git commit -m "feat: add JACK_USAGE metadata and jack_usage helper" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Single-source the inline usage strings

No new behavior. Existing tests are the safety net: they already assert usage output for several actions.

**Files:**
- Modify: `lib/*.sh` (every inline `usage:` string)

**Step 1: Mechanical replace**

Run from the repo root:

```bash
perl -pi -e 's/die_usage "usage: jack (\w+) ([a-z-]+)[^"]*"/die_usage "usage: \$(jack_usage $1 $2)"/; s/parse_yes_only "jack (\w+) ([a-z-]+)[^"]*"/parse_yes_only "\$(jack_usage $1 $2)"/' lib/*.sh
git diff --stat
```

Expected: changes in docker, git, mac, npm, port, ubuntu. `lib/core.sh`, `lib/mysql.sh` and the ubuntu `local usage=` line are untouched, since they don't match.

**Step 2: Fix the remaining three by hand**

`lib/core.sh`, in `ssh_keygen_for`, replace
`die_usage "usage: jack $theme ssh-key <email>"` with
`die_usage "usage: $(jack_usage "$theme" ssh-key)"`.

`lib/mysql.sh` line 6, replace with
`local usage="usage: $(jack_usage mysql dump)"`.

`lib/ubuntu.sh` in `ubuntu_big_files_delete`, replace the `local usage=` line with
`local usage="usage: $(jack_usage ubuntu big-files-delete)"`.

**Step 3: Verify nothing is left**

Run: `grep -n 'usage: jack' lib/*.sh`
Expected: no output.

Run: `bats tests/`
Expected: all PASS, same count as the end of Task 1.

**Step 4: Commit**

```bash
git add lib
git commit -m "refactor: read usage strings from JACK_USAGE metadata" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: help dispatch

**Files:**
- Modify: `lib/core.sh` (add `jack_desc`)
- Modify: `bin/jack`
- Test: `tests/dispatch.bats`

**Step 1: Write the failing tests**

Append to `tests/dispatch.bats`:

```bash
@test "help lists themes like no args" {
  run "$JACK" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"List and kill processes on TCP ports"* ]]
}

@test "theme help lists actions" {
  run "$JACK" port help
  [ "$status" -eq 0 ]
  [[ "$output" == *"kill"* ]]
}

@test "action help words print doc and usage without running the action" {
  local word
  for word in -h --help help; do
    run "$JACK" port kill "$word"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Kill whatever listens on a port"* ]]
    [[ "$output" == *"usage: jack port kill <port> [-y]"* ]]
  done
}

@test "action help on a no-arg action has no trailing space" {
  run "$JACK" git remote-url -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: jack git remote-url" ]]
}

@test "help for an unknown action still exits 2" {
  run "$JACK" port nope -h
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown action"* ]]
}
```

**Step 2: Run to verify failure**

Run: `bats tests/dispatch.bats`
Expected: the five new tests FAIL (`help` is read as an unknown theme, `-h` reaches the action).

**Step 3: Implement**

In `lib/core.sh`, after `jack_usage`:

```bash
jack_desc() {
  sed -n 's/^JACK_DESC="\(.*\)"$/\1/p' "$JACK_ROOT/lib/$1.sh" | head -n 1
}
```

In `bin/jack`, replace the `desc="$(sed ...)"` line in `list_themes` with `desc="$(jack_desc "$name")"`, then add above `main`:

```bash
action_help() {
  jack_meta "$1" DOC "$(printf %s "$2" | tr - _)"
  echo
  echo "usage: $(jack_usage "$1" "$2")"
}
```

Change the top-level condition in `main` to:

```bash
  if [ -z "$theme" ] || [ "$theme" = -h ] || [ "$theme" = --help ] || [ "$theme" = help ]; then
```

Change the empty-action condition to:

```bash
  if [ -z "$action" ] || [ "$action" = help ]; then
```

`jack port help` is a theme-level word, so it must be checked before the action is validated. Then, after the `declare -F` check and before `shift 2`:

```bash
  case "${3:-}" in
    -h|--help|help) action_help "$theme" "$action"; return 0 ;;
  esac
```

**Step 4: Run to verify pass**

Run: `bats tests/`
Expected: all PASS.

**Step 5: Commit**

```bash
git add bin lib tests
git commit -m "feat: add help and -h at theme and action level" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: hidden __complete command

**Files:**
- Modify: `lib/core.sh`
- Modify: `bin/jack`
- Test: `tests/complete.bats` (create)

**Step 1: Write the failing tests**

Create `tests/complete.bats`:

```bash
#!/usr/bin/env bats

setup() {
  JACK="$BATS_TEST_DIRNAME/../bin/jack"
}

has_line() {
  printf '%s\n' "$output" | grep -qxF -- "$1"
}

@test "position 1 lists themes and help" {
  run "$JACK" __complete ""
  [ "$status" -eq 0 ]
  has_line port
  has_line docker
  has_line help
  ! has_line core
}

@test "a partial first word still lists all themes" {
  run "$JACK" __complete po
  has_line port
  has_line docker
}

@test "position 2 lists hyphenated actions and help" {
  run "$JACK" __complete mac ""
  [ "$status" -eq 0 ]
  has_line flush-dns
  has_line nginx-reload
  has_line help
}

@test "unknown or malformed theme prints nothing and exits 0" {
  run "$JACK" __complete nope ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run "$JACK" __complete ../lib/core ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run "$JACK" __complete core ""
  [ -z "$output" ]
}

@test "later positions print nothing" {
  run "$JACK" __complete port kill ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "--desc adds the doc after a colon" {
  run "$JACK" __complete --desc port ""
  has_line "kill:Kill whatever listens on a port, SIGTERM then SIGKILL"
  has_line "help:Show help"
  run "$JACK" __complete --desc ""
  has_line "port:List and kill processes on TCP ports"
}
```

**Step 2: Run to verify failure**

Run: `bats tests/complete.bats`
Expected: FAIL (`unknown theme: __complete`).

**Step 3: Implement**

Append to `lib/core.sh`:

```bash
_jack_candidate() {
  if [ "$JACK_COMPLETE_DESC" -eq 1 ]; then
    printf '%s:%s\n' "$1" "$2"
  else
    printf '%s\n' "$1"
  fi
}

jack_complete() {
  JACK_COMPLETE_DESC=0
  if [ "${1:-}" = --desc ]; then
    JACK_COMPLETE_DESC=1
    shift
  fi
  local name act
  case $# in
    0|1)
      for name in $(jack_themes); do
        _jack_candidate "$name" "$(jack_desc "$name")"
      done
      _jack_candidate help "Show help"
      ;;
    2)
      case "$1" in
        ''|*[!a-z]*) return 0 ;;
      esac
      { [ "$1" != core ] && [ -f "$JACK_ROOT/lib/$1.sh" ]; } || return 0
      for act in $(jack_actions "$1"); do
        _jack_candidate "$(printf %s "$act" | tr _ -)" "$(jack_meta "$1" DOC "$act")"
      done
      _jack_candidate help "Show help"
      ;;
  esac
  return 0
}
```

In `bin/jack` `main`, immediately after the `local` line:

```bash
  if [ "$theme" = __complete ]; then
    shift
    jack_complete "$@"
    return 0
  fi
```

**Step 4: Run to verify pass**

Run: `bats tests/`
Expected: all PASS.

**Step 5: Commit**

```bash
git add bin lib tests
git commit -m "feat: add hidden __complete candidate generator" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: completion theme

**Files:**
- Create: `lib/completion.sh`
- Test: `tests/completion.bats` (create)

**Step 1: Write the failing tests**

Create `tests/completion.bats`:

```bash
#!/usr/bin/env bats

setup() {
  JACK="$BATS_TEST_DIRNAME/../bin/jack"
  JACK_BIN_DIR="$(cd "$BATS_TEST_DIRNAME/../bin" && pwd)"
}

bash_complete() {
  bash -c 'PATH="$1:$PATH"; eval "$(jack completion bash)"; COMP_WORDS=("${@:2}"); COMP_CWORD=$(($# - 2)); _jack_complete; printf "%s\n" "${COMPREPLY[@]}"' _ "$JACK_BIN_DIR" "$@"
}

@test "completion bash prints a script that passes bash -n" {
  run "$JACK" completion bash
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/jack.bash"
  run bash -n "$BATS_TEST_TMPDIR/jack.bash"
  [ "$status" -eq 0 ]
}

@test "completion zsh prints a script that passes zsh -n" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run "$JACK" completion zsh
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/jack.zsh"
  run zsh -n "$BATS_TEST_TMPDIR/jack.zsh"
  [ "$status" -eq 0 ]
}

@test "unknown shell exits 2" {
  run "$JACK" completion fish
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown action"* ]]
}

@test "bash completion completes themes by prefix" {
  run bash_complete jack po
  [ "$status" -eq 0 ]
  [ "$output" = "port" ]
}

@test "bash completion completes actions by prefix" {
  run bash_complete jack port ki
  [ "$output" = "kill" ]
}

@test "bash completion offers every action on an empty word" {
  run bash_complete jack mac ""
  [[ "$output" == *"flush-dns"* ]]
  [[ "$output" == *"nginx-reload"* ]]
}

@test "zsh completion registers _jack for jack" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -f -c 'PATH="$1:$PATH"; autoload -Uz compinit; compinit -u -d "$2"; eval "$(jack completion zsh)"; print -r -- "${_comps[jack]}"' _ "$JACK_BIN_DIR" "$BATS_TEST_TMPDIR/zcompdump"
  [ "$status" -eq 0 ]
  [ "$output" = "_jack" ]
}
```

**Step 2: Run to verify failure**

Run: `bats tests/completion.bats`
Expected: FAIL (`unknown theme: completion`).

**Step 3: Implement**

Create `lib/completion.sh`:

```bash
JACK_DESC="Emit shell completion scripts"
JACK_DOC_zsh="Print the zsh completion script, for eval in .zshrc after compinit"
JACK_USAGE_zsh=""
JACK_DOC_bash="Print the bash completion script, for eval in .bashrc"
JACK_USAGE_bash=""

completion_zsh() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage completion zsh)"
  cat <<'EOF'
_jack() {
  local -a items
  items=(${(f)"$(jack __complete --desc "${(@)words[2,CURRENT]}" 2>/dev/null)"})
  (( ${#items} )) && _describe 'jack' items
}
(( $+functions[compdef] )) && compdef _jack jack
EOF
}

completion_bash() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage completion bash)"
  cat <<'EOF'
_jack_complete() {
  local IFS=$'\n'
  COMPREPLY=($(compgen -W "$(jack __complete "${COMP_WORDS[@]:1:COMP_CWORD}" 2>/dev/null)" -- "${COMP_WORDS[COMP_CWORD]}"))
}
complete -F _jack_complete jack
EOF
}
```

**Step 4: Run to verify pass**

Run: `bats tests/`
Expected: all PASS, including the `meta.bats` DOC and USAGE checks for the new theme.

If the zsh registration test fails because `compdef` is missing under `zsh -f -c`, check that `compinit` ran in that shell and that `-d` points to a writable path before changing the script.

**Step 5: Manual check in a real shell**

In a throwaway zsh (`zsh -f`), run:

```zsh
autoload -Uz compinit && compinit
eval "$(/Users/burak/Projects/jack-all-trades/bin/jack completion zsh)"
alias jack=/Users/burak/Projects/jack-all-trades/bin/jack
```

Type `jack po<TAB>` and `jack port <TAB>`. Expected: `port`, then `list` and `kill` with descriptions. Report what you see, since bats can't drive zsh's menu.

**Step 6: Commit**

```bash
git add lib tests
git commit -m "feat: add completion theme for zsh and bash" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: README

**Files:**
- Modify: `README.md`

**Step 1: Edit**

In the `Use` code block, add after `jack alias print`:

```bash
jack help               # same as jack
jack port kill -h       # doc and usage for one action
```

Add a section after `### Aliases`:

````markdown
### Completion

```bash
command -v jack >/dev/null && eval "$(jack completion zsh)"
```

Use `bash` instead of `zsh` in `.bashrc`. In `.zshrc`, put the line after `compinit`, otherwise nothing registers.
````

In `## Add a theme`, change the sentence about docs to: "Every action needs a `JACK_DOC_<action>="one line"` and a `JACK_USAGE_<action>="args"` assignment, and may add `JACK_ALIAS_<action>="name"`. Use an empty usage for actions without arguments. Error messages should call `jack_usage <theme> <action>` instead of repeating the string."

Update the sentence "Tests fail when a doc is missing or an alias repeats." to "Tests fail when a doc or usage is missing or an alias repeats."

Add `completion` to the `Themes:` list.

**Step 2: Verify**

Run: `bats tests/`
Expected: all PASS.

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: document completion, help and JACK_USAGE" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```
