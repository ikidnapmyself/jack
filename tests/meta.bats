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

@test "themes and actions are discovered" {
  [ -n "$(jack_themes)" ]
  [ -n "$(jack_actions port)" ]
}

@test "every public action has a JACK_USAGE" {
  local theme act missing=""
  for theme in $(jack_themes); do
    for act in $(jack_actions "$theme"); do
      grep -q "^JACK_USAGE_$act=\".*\"\$" "$JACK_ROOT/lib/$theme.sh" || missing="$missing $theme/$act"
    done
  done
  [ -z "$missing" ] || { echo "missing JACK_USAGE:$missing"; return 1; }
}
