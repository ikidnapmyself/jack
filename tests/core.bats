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
