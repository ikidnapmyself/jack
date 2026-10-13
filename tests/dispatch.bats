#!/usr/bin/env bats

setup() {
  JACK="$BATS_TEST_DIRNAME/../bin/jack"
}

@test "no args lists themes with descriptions" {
  run "$JACK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"port"* ]]
  [[ "$output" == *"List and kill processes on TCP ports"* ]]
}

@test "core is not exposed as a theme" {
  run "$JACK"
  [[ "$output" != *"core"* ]]
  run "$JACK" core
  [ "$status" -eq 2 ]
}

@test "unknown theme exits 2" {
  run "$JACK" nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown theme"* ]]
}

@test "theme name with path characters exits 2" {
  run "$JACK" ../lib/core
  [ "$status" -eq 2 ]
}

@test "works through a symlink" {
  ln -s "$JACK" "$BATS_TEST_TMPDIR/jack"
  run "$BATS_TEST_TMPDIR/jack"
  [ "$status" -eq 0 ]
  [[ "$output" == *"port"* ]]
}
