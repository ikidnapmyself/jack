#!/usr/bin/env bats

setup() {
  INSTALL="$BATS_TEST_DIRNAME/../install.sh"
  SRC="$BATS_TEST_TMPDIR/src"
  mkdir -p "$SRC"
  cp -R "$BATS_TEST_DIRNAME/../bin" "$BATS_TEST_DIRNAME/../lib" "$SRC/"
  rm -rf "$SRC/lib/vendor"
  git -C "$SRC" init --quiet --initial-branch=main
  git -C "$SRC" add .
  git -C "$SRC" -c user.name=t -c user.email=t@t commit --quiet -m init

  export JACK_REPO="$SRC"
  export JACK_DIR="$BATS_TEST_TMPDIR/share/jack"
  export JACK_BIN_DIR="$BATS_TEST_TMPDIR/bin"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

@test "installs and links jack" {
  run sh "$INSTALL"
  [ "$status" -eq 0 ]
  [ -L "$JACK_BIN_DIR/jack" ]
  [[ "$output" == *"installed jack "* ]]
  run "$JACK_BIN_DIR/jack" --version
  [ "$status" -eq 0 ]
}

@test "prints PATH hint when bin dir is missing from PATH" {
  run sh "$INSTALL"
  [[ "$output" == *"isn't on your PATH"* ]]
}

@test "skips PATH hint when bin dir is on PATH" {
  PATH="$JACK_BIN_DIR:$PATH" run sh "$INSTALL"
  [ "$status" -eq 0 ]
  [[ "$output" != *"isn't on your PATH"* ]]
}

@test "rerun updates an existing checkout" {
  sh "$INSTALL" >/dev/null
  echo "# new" >> "$SRC/lib/core.sh"
  git -C "$SRC" -c user.name=t -c user.email=t@t commit --quiet -am update
  run sh "$INSTALL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"updating"* ]]
  [ "$(git -C "$JACK_DIR" rev-parse HEAD)" = "$(git -C "$SRC" rev-parse HEAD)" ]
}

@test "refuses a non-jack directory" {
  mkdir -p "$JACK_DIR"
  run sh "$INSTALL"
  [ "$status" -ne 0 ]
  [[ "$output" == *"isn't a jack checkout"* ]]
}

@test "refuses to replace a foreign binary" {
  mkdir -p "$JACK_BIN_DIR"
  echo other > "$JACK_BIN_DIR/jack"
  run sh "$INSTALL"
  [ "$status" -ne 0 ]
  [ "$(cat "$JACK_BIN_DIR/jack")" = other ]
  [ ! -e "$JACK_DIR" ]
}

@test "uninstall removes link and checkout" {
  sh "$INSTALL" >/dev/null
  run sh "$INSTALL" --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$JACK_BIN_DIR/jack" ]
  [ ! -e "$JACK_DIR" ]
}

@test "unknown option fails" {
  run sh "$INSTALL" --nope
  [ "$status" -ne 0 ]
}
