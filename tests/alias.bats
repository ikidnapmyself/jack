#!/usr/bin/env bats

load test_helper

setup() {
  mkdir -p "$BATS_TEST_TMPDIR/root"
  cp -R "$BATS_TEST_DIRNAME/../bin" "$BATS_TEST_DIRNAME/../lib" "$BATS_TEST_TMPDIR/root/"
  printf 'JACK_DESC="fixture"\nJACK_DOC_two_words="Say ok"\nJACK_ALIAS_two_words="twow"\nJACK_DOC_plain="No alias"\nfx_two_words() { echo ok; }\nfx_plain() { echo ok; }\n' > "$BATS_TEST_TMPDIR/root/lib/fx.sh"
  FXJACK="$BATS_TEST_TMPDIR/root/bin/jack"
}

@test "print emits an alias line per JACK_ALIAS" {
  run "$FXJACK" alias print
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias twow='jack fx two-words'"* ]]
}

@test "print skips actions without an alias" {
  run "$FXJACK" alias print
  [[ "$output" != *"plain"* ]]
}

@test "print output can be eval-ed" {
  run bash -c 'eval "$("$1" alias print)" && alias twow' _ "$FXJACK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jack fx two-words"* ]]
}
