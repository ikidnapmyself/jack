JACK_DESC="Browse every theme's actions"
JACK_ABOUT="Built-in reference. Lists what every theme and action does and explains each one in plain terms, including whether it is safe to run. Read-only, it changes nothing."
JACK_DOC_list="List actions with descriptions, optionally for one theme"
JACK_USAGE_list="[theme]"
JACK_DOC_explain="Explain what a theme or action does and whether it is safe"
JACK_USAGE_explain="[theme] [action]"
JACK_INFO_list="Prints every action with its one-line description, for all themes or just one."
JACK_INFO_explain="Explains a theme or an action in plain terms: what it does, what it changes and whether it is safe. With no arguments it describes every theme. With tuin on, it opens a menu to browse."

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
    if jack_theme_visible "$theme"; then echo "$theme"; else echo "$theme (Disabled)"; fi
    jack_print_actions "$theme"
  done
}

_cheat_check_theme() {
  case "$1" in
    *[!a-z]*) die_usage "unknown theme: $1" ;;
  esac
  [ "$1" != core ] && [ -f "$JACK_ROOT/lib/$1.sh" ] || die_usage "unknown theme: $1"
}

_cheat_wrap() {
  printf '%s\n' "$2" | fold -s -w 76 | sed "s/^/$1/"
}

_cheat_theme_text() {
  printf '%s: %s\n' "$1" "$(jack_desc "$1")"
  _cheat_wrap '' "$(jack_about "$1")"
}

_cheat_action_text() {
  local theme="$1" act
  act="$(printf %s "$2" | tr - _)"
  printf '%s\n' "$(jack_usage "$theme" "$act")"
  _cheat_wrap '  ' "$(jack_meta "$theme" DOC "$act")"
  _cheat_wrap '  ' "$(jack_meta "$theme" INFO "$act")"
}

_cheat_browse() {
  local theme act
  local -a opts
  while true; do
    opts=()
    for theme in $(jack_visible_themes); do
      opts+=("$(printf '%-12s %s' "$theme" "$(jack_desc "$theme")")")
    done
    tuin_menu "explain" "${opts[@]}" || return 0
    theme="${TUIN_REPLY%% *}"
    opts=("$(printf '%-18s %s' overview "What $theme is and whether it is safe")")
    for act in $(jack_actions "$theme"); do
      opts+=("$(printf '%-18s %s' "$(printf %s "$act" | tr _ -)" "$(jack_meta "$theme" DOC "$act")")")
    done
    while tuin_menu "explain $theme" "${opts[@]}"; do
      echo
      case "$TUIN_REPLY" in
        overview*) _cheat_theme_text "$theme" ;;
        *) _cheat_action_text "$theme" "${TUIN_REPLY%% *}" ;;
      esac
      echo
    done
  done
}

cheat_explain() {
  [ $# -le 2 ] || die_usage "usage: $(jack_usage cheat explain)"
  local theme="${1:-}" act="${2:-}" a

  if [ -z "$theme" ]; then
    if [ "$JACK_TUIN_ON" -eq 1 ] && [ -t 0 ] && [ -t 1 ]; then
      _cheat_browse
      return 0
    fi
    for theme in $(jack_visible_themes); do
      _cheat_theme_text "$theme"
      echo
    done
    return 0
  fi

  _cheat_check_theme "$theme"
  if [ -z "$act" ]; then
    _cheat_theme_text "$theme"
    for a in $(jack_actions "$theme"); do
      echo
      _cheat_action_text "$theme" "$a"
    done
    return 0
  fi

  act="$(printf %s "$act" | tr - _)"
  case " $(jack_actions "$theme" | tr '\n' ' ') " in
    *" $act "*) ;;
    *) die_usage "unknown action: $theme $(printf %s "$act" | tr _ -)" ;;
  esac
  _cheat_action_text "$theme" "$act"
}
