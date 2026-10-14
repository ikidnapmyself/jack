JACK_DESC="Emit shell aliases for jack actions"
JACK_DOC_print="Print one alias line per aliased action, for eval in your shell rc"
JACK_USAGE_print=""

alias_print() {
  local theme act name
  for theme in $(jack_themes); do
    for act in $(jack_actions "$theme"); do
      name="$(jack_meta "$theme" ALIAS "$act")"
      [ -n "$name" ] || continue
      printf "alias %s='jack %s %s'\n" "$name" "$theme" "$(printf %s "$act" | tr _ -)"
    done
  done
}
