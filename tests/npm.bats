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
