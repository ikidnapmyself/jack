#!/usr/bin/env bats

setup() {
  JACK="$BATS_TEST_DIRNAME/../bin/jack"
  JACK_BIN_DIR="$(cd "$BATS_TEST_DIRNAME/../bin" && pwd)"
}

bash_complete() {
  bash -c 'PATH="$1:$PATH"; eval "$(jack completion bash)"; COMP_WORDS=("${@:2}"); COMP_CWORD=$(($# - 2)); _jack_complete; printf "%s\n" "${COMPREPLY[@]}"' _ "$JACK_BIN_DIR" "$@"
}

@test "completion bash prints a script that passes bash -n" {
  run "$JACK" completion bash
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/jack.bash"
  run bash -n "$BATS_TEST_TMPDIR/jack.bash"
  [ "$status" -eq 0 ]
}

@test "completion zsh prints a script that passes zsh -n" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run "$JACK" completion zsh
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  printf '%s\n' "$output" > "$BATS_TEST_TMPDIR/jack.zsh"
  run zsh -n "$BATS_TEST_TMPDIR/jack.zsh"
  [ "$status" -eq 0 ]
}

@test "unknown shell exits 2" {
  run "$JACK" completion fish
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown action"* ]]
}

@test "bash completion completes themes by prefix" {
  run bash_complete jack po
  [ "$status" -eq 0 ]
  [ "$output" = "port" ]
}

@test "bash completion completes actions by prefix" {
  run bash_complete jack port ki
  [ "$output" = "kill" ]
}

@test "bash completion offers every action on an empty word" {
  run bash_complete jack mac ""
  [[ "$output" == *"flush-dns"* ]]
  [[ "$output" == *"nginx-reload"* ]]
}

@test "zsh completion registers _jack for jack" {
  command -v zsh >/dev/null || skip "zsh not installed"
  run zsh -f -c 'PATH="$1:$PATH"; autoload -Uz compinit; compinit -u -d "$2"; eval "$(jack completion zsh)"; print -r -- "${_comps[jack]}"' _ "$JACK_BIN_DIR" "$BATS_TEST_TMPDIR/zcompdump"
  [ "$status" -eq 0 ]
  [ "$output" = "_jack" ]
}
