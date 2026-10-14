JACK_DESC="Browse every theme's actions"
JACK_DOC_list="List actions with descriptions, optionally for one theme"

cheat_list() {
  local only="${1:-}" theme
  if [ -n "$only" ]; then
    case "$only" in
      *[!a-z]*) die_usage "unknown theme: $only" ;;
    esac
    [ "$only" != core ] && [ -f "$JACK_ROOT/lib/$only.sh" ] || die_usage "unknown theme: $only"
  fi
  for theme in $(jack_themes); do
    [ -z "$only" ] || [ "$only" = "$theme" ] || continue
    echo "$theme"
    jack_print_actions "$theme"
  done
}
