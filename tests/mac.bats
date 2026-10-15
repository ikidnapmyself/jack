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

@test "ssh-key uses the shared helper" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  stub_cmd ssh-keygen ''
  run "$JACK" mac ssh-key me@example.com
  [ "$status" -eq 0 ]
  logged "ssh-keygen -t ed25519 -C me@example.com -f $HOME/.ssh/id_ed25519"
}
