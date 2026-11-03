#!/usr/bin/env bats

load test_helper

setup() {
  JACK_ROOT="$BATS_TEST_DIRNAME/.."
  export JACK_CONFIG_DIR="$BATS_TEST_TMPDIR/config"
  export JACK_TUIN_FILE="$BATS_TEST_TMPDIR/tuin.sh"
  mkdir -p "$JACK_CONFIG_DIR"
  cat > "$JACK_TUIN_FILE" <<'STUB'
tuin_confirm() { echo "tuin_confirm $1 $2"; return 0; }
tuin_spin() { echo "tuin_spin $1"; shift 2; "$@"; }
STUB
}

@test "tuin stays unloaded without opt-in" {
  . "$JACK_ROOT/lib/core.sh"
  [ "$JACK_TUIN_ON" -eq 0 ]
  ! declare -F tuin_confirm >/dev/null
}

@test "tuin stays unloaded when state is off" {
  echo off > "$JACK_CONFIG_DIR/tuin"
  . "$JACK_ROOT/lib/core.sh"
  [ "$JACK_TUIN_ON" -eq 0 ]
}

@test "tuin stays unloaded when the vendored file is missing" {
  echo on > "$JACK_CONFIG_DIR/tuin"
  rm "$JACK_TUIN_FILE"
  . "$JACK_ROOT/lib/core.sh"
  [ "$JACK_TUIN_ON" -eq 0 ]
}

@test "confirm uses tuin_confirm when enabled" {
  echo on > "$JACK_CONFIG_DIR/tuin"
  . "$JACK_ROOT/lib/core.sh"
  run confirm "Go?"
  [ "$status" -eq 0 ]
  [ "$output" = "tuin_confirm Go? n" ]
}

@test "jack_spin uses tuin_spin when enabled" {
  echo on > "$JACK_CONFIG_DIR/tuin"
  . "$JACK_ROOT/lib/core.sh"
  run jack_spin "Working" echo hi
  [ "$output" = "$(printf 'tuin_spin Working\nhi')" ]
}

@test "jack_spin runs the command plainly when disabled" {
  . "$JACK_ROOT/lib/core.sh"
  run jack_spin "Working" echo hi
  [ "$output" = "hi" ]
}

@test "jack_tuin_offer does nothing without a tty" {
  . "$JACK_ROOT/lib/core.sh"
  run jack_tuin_offer
  [ -z "$output" ]
  [ ! -e "$JACK_CONFIG_DIR/tuin" ]
}

@test "bare jack without a tty prints the theme list and never prompts" {
  run "$JACK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"themes:"* ]]
  [ ! -e "$JACK_CONFIG_DIR/tuin" ]
}

@test "port kill picker lists each listening port once" {
  . "$JACK_ROOT/lib/port.sh"
  port="$(free_port)"
  start_listener "$port"
  run _port_pick_kill
  stop_listener
  [[ "$output" == "$port  "* ]]
  [ "$(printf '%s\n' "$output" | grep -c "^$port ")" -eq 1 ]
}

@test "docker restart picker prints compose services" {
  . "$JACK_ROOT/lib/docker.sh"
  setup_stubs
  stub_cmd docker-compose 'printf "web\ndb\n"'
  run _docker_pick_restart
  [ "$output" = "$(printf 'web\ndb')" ]
}

@test "docker restart picker is silent without docker-compose" {
  . "$JACK_ROOT/lib/docker.sh"
  PATH="/usr/bin:/bin" run _docker_pick_restart
  [ -z "$output" ]
}

@test "every picker belongs to an existing action" {
  for f in "$JACK_ROOT"/lib/*.sh; do
    theme="$(basename "$f" .sh)"
    for fn in $(sed -n "s/^_${theme}_pick_\([a-z_]*\)()[[:space:]]*{.*/\1/p" "$f"); do
      grep -q "^${theme}_${fn}()" "$f"
    done
  done
}

@test "tuin enable skips the download when the file exists and turns it on" {
  run "$JACK" tuin enable
  [ "$status" -eq 0 ]
  [ "$(cat "$JACK_CONFIG_DIR/tuin")" = on ]
}

@test "tuin disable turns it off" {
  echo on > "$JACK_CONFIG_DIR/tuin"
  run "$JACK" tuin disable
  [ "$status" -eq 0 ]
  [ "$(cat "$JACK_CONFIG_DIR/tuin")" = off ]
}

@test "tuin status reports state and file" {
  echo on > "$JACK_CONFIG_DIR/tuin"
  run "$JACK" tuin status
  [[ "$output" == *"state    on"* ]]
  [[ "$output" == *"(present)"* ]]
}

@test "tuin enable fails cleanly when the download fails" {
  rm "$JACK_TUIN_FILE"
  setup_stubs
  stub_cmd curl 'exit 22'
  run "$JACK" tuin enable
  [ "$status" -eq 1 ]
  [[ "$output" == *"download failed"* ]]
  [ ! -e "$JACK_CONFIG_DIR/tuin" ]
}

@test "default tuin file is not loaded when its checksum mismatches" {
  echo on > "$JACK_CONFIG_DIR/tuin"
  unset JACK_TUIN_FILE
  JACK_ROOT="$BATS_TEST_TMPDIR/root"
  mkdir -p "$JACK_ROOT/lib/vendor"
  cp "$BATS_TEST_DIRNAME/../lib/core.sh" "$JACK_ROOT/lib/core.sh"
  echo 'tuin_confirm() { :; }' > "$JACK_ROOT/lib/vendor/tuin.sh"
  run bash -c ". '$JACK_ROOT/lib/core.sh'; echo on=\$JACK_TUIN_ON"
  [[ "$output" == *"checksum mismatch"* ]]
  [[ "$output" == *"on=0"* ]]
}

@test "JACK_TUIN_FILE override is ignored as root" {
  setup_stubs
  echo on > "$JACK_CONFIG_DIR/tuin"
  stub_cmd id 'echo 0'
  . "$JACK_ROOT/lib/core.sh"
  [ "$JACK_TUIN_ON" -eq 0 ]
}
