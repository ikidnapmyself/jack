JACK_DESC="Turn the tuin UI on or off"
JACK_ABOUT="Switches the optional interactive interface on or off. That means arrow-key menus, spinners and confirm prompts. It only changes how jack looks and asks, never what an action does. The download is checksum-verified."
JACK_DOC_enable="Download tuin if needed and turn on menus, spinners and prompts"
JACK_DOC_disable="Turn the tuin UI off, keeps the downloaded file"
JACK_DOC_status="Show whether tuin is on, its version and where the file lives"
JACK_USAGE_enable=""
JACK_USAGE_disable=""
JACK_USAGE_status=""
JACK_INFO_enable="Downloads tuin if it is missing, checks its checksum, and turns on menus, spinners and arrow-key prompts. Needs curl and network the first time."
JACK_INFO_disable="Turns the interactive interface off. The downloaded file is kept so enable is instant later."
JACK_INFO_status="Shows whether tuin is on, its version and where the file lives. Read-only."

tuin_enable() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage tuin enable)"
  if [ ! -f "$JACK_TUIN_FILE" ]; then
    echo "downloading tuin v$JACK_TUIN_VERSION"
    jack_tuin_install || return 1
  fi
  jack_tuin_set on || die "cannot write $JACK_TUIN_STATE"
  echo "tuin is on, installed at $JACK_TUIN_FILE"
}

tuin_disable() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage tuin disable)"
  jack_tuin_set off || die "cannot write $JACK_TUIN_STATE"
  echo "tuin is off"
}

tuin_status() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage tuin status)"
  local state file=missing
  state="$(jack_tuin_state)"
  [ -f "$JACK_TUIN_FILE" ] && file=present
  printf 'state    %s\n' "${state:-unset}"
  printf 'version  %s\n' "$JACK_TUIN_VERSION"
  printf 'file     %s (%s)\n' "$JACK_TUIN_FILE" "$file"
}
