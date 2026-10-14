#!/usr/bin/env bats

load test_helper

setup() {
  setup_stubs
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
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
  PATH="$STUB_DIR:/usr/bin:/bin"
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
  [[ "$output" == *"usage: jack clean pip"* ]] || false
  not_logged_like "^pip"
}

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
  [[ "$output" == *"usage: jack clean npm"* ]] || false
  not_logged_like "^npm"
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
  [[ "$output" == *"usage: jack clean docker"* ]] || false
  not_logged_like "^docker"
}

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
  [[ "$output" == *"brew is for macOS only"* ]] || false
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
  [[ "$output" == *"sudo jack clean apt"* ]] || false
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

@test "snap with no disabled revisions has nothing to remove" {
  export JACK_UNAME=Linux
  stub_cmd id 'echo 0'
  stub_cmd snap ''
  run "$JACK" clean snap -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to remove"* ]]
}
