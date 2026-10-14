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
