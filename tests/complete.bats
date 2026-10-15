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
  has_line ssh-key
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

@test "themes for another OS are hidden from completion" {
  JACK_UNAME=Linux run "$JACK" __complete ""
  has_line ubuntu
  ! has_line mac
  JACK_UNAME=Darwin run "$JACK" __complete ""
  has_line mac
  ! has_line ubuntu
}
