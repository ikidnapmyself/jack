JACK_DESC="NPM chores"
JACK_DOC_cache_clear="Force-clear the npm cache"
JACK_ALIAS_cache_clear="npmcc"
JACK_DOC_global_setup="Point global installs at ~/.npm-global and add it to PATH in ~/.profile"
JACK_USAGE_cache_clear=""
JACK_USAGE_global_setup="[-y]"

npm_cache_clear() {
  [ $# -eq 0 ] || die_usage "usage: jack npm cache-clear"
  require_cmd npm
  npm cache clear --force
}

npm_global_setup() {
  parse_yes_only "jack npm global-setup [-y]" "$@"
  require_cmd npm
  local dir="$HOME/.npm-global" profile="$HOME/.profile"
  local line='export PATH=~/.npm-global/bin:$PATH'
  confirm_unless_yes "Set npm prefix to $dir and edit $profile?" "$ASSUME_YES" || return 1
  mkdir -p "$dir"
  npm config set prefix "$dir" || die "npm config failed"
  if grep -qxF "$line" "$profile" 2>/dev/null; then
    echo "$profile already exports $dir/bin"
  else
    printf '%s\n' "$line" >> "$profile"
    echo "added PATH export to $profile"
  fi
}
