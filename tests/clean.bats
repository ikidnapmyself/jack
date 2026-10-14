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
