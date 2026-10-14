#!/usr/bin/env bats

setup() {
  JACK_ROOT="$BATS_TEST_DIRNAME/.."
  . "$JACK_ROOT/lib/core.sh"
}

@test "every public action has a JACK_DOC" {
  local theme act missing=""
  for theme in $(jack_themes); do
    for act in $(jack_actions "$theme"); do
      [ -n "$(jack_meta "$theme" DOC "$act")" ] || missing="$missing $theme/$act"
    done
  done
  [ -z "$missing" ] || { echo "missing JACK_DOC:$missing"; return 1; }
}

@test "aliases are unique and well formed" {
  local theme act name seen=" "
  for theme in $(jack_themes); do
    for act in $(jack_actions "$theme"); do
      name="$(jack_meta "$theme" ALIAS "$act")"
      [ -n "$name" ] || continue
      case "$name" in
        [a-z]*) ;;
        *) echo "bad alias: $name"; return 1 ;;
      esac
      case "$name" in
        *[!a-z0-9]*) echo "bad alias: $name"; return 1 ;;
      esac
      case "$seen" in
        *" $name "*) echo "duplicate alias: $name"; return 1 ;;
      esac
      seen="$seen$name "
    done
  done
}
