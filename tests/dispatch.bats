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

@test "theme alone lists public actions only" {
  run "$JACK" port
  [ "$status" -eq 0 ]
  [[ "$output" == *"list"* ]]
  [[ "$output" == *"kill"* ]]
  [[ "$output" != *"validate"* ]]
  [[ "$output" != *"cmdline"* ]]
}

@test "unknown action exits 2" {
  run "$JACK" port nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown action"* ]]
}

@test "helper functions are not callable as actions" {
  run "$JACK" port _rows
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown action"* ]]
}

@test "theme alone shows action docs" {
  run "$JACK" port
  [[ "$output" == *"Kill whatever listens on a port"* ]]
}

@test "hyphenated action runs the underscore function" {
  mkdir -p "$BATS_TEST_TMPDIR/root"
  cp -R "$BATS_TEST_DIRNAME/../bin" "$BATS_TEST_DIRNAME/../lib" "$BATS_TEST_TMPDIR/root/"
  printf 'JACK_DESC="fixture"\nJACK_DOC_two_words="Say ok"\nfx_two_words() { echo ok; }\n' > "$BATS_TEST_TMPDIR/root/lib/fx.sh"
  run "$BATS_TEST_TMPDIR/root/bin/jack" fx two-words
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
  run "$BATS_TEST_TMPDIR/root/bin/jack" fx
  [[ "$output" == *"two-words"* ]]
  [[ "$output" == *"Say ok"* ]]
}
