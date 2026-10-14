JACK_DESC="Cache and disk cleanup"
JACK_DOC_pip="Purge the pip cache"
JACK_DOC_yarn="Clean the Yarn cache"
JACK_DOC_pnpm="Prune the pnpm store"
JACK_DOC_composer="Clear the Composer cache"
JACK_DOC_go="Clean the Go module cache"
JACK_DOC_npm="Force-clear the npm cache"
JACK_DOC_docker="Remove unused Docker containers, networks, images and cache"
JACK_USAGE_pip=""
JACK_USAGE_yarn=""
JACK_USAGE_pnpm=""
JACK_USAGE_composer=""
JACK_USAGE_go=""
JACK_USAGE_npm=""
JACK_USAGE_docker="[-y]"
JACK_DOC_brew="Remove all Homebrew cache, macOS only"
JACK_DOC_xcode="Delete Xcode DerivedData, macOS only"
JACK_DOC_apt="Clear the APT package cache, Linux, needs root"
JACK_DOC_journal="Trim systemd journal logs to 100M, Linux, needs root"
JACK_DOC_snap="Remove disabled snap revisions, Linux, needs root"
JACK_USAGE_brew=""
JACK_USAGE_xcode="[-y]"
JACK_USAGE_apt=""
JACK_USAGE_journal=""
JACK_USAGE_snap="[-y]"
JACK_DOC_gradle="Stop the Gradle daemon and delete ~/.gradle/caches"
JACK_DOC_maven="Delete Maven SNAPSHOT artifacts older than 90 days"
JACK_DOC_cargo="Autoclean the cargo cache, installs cargo-cache if missing"
JACK_USAGE_gradle="[-y]"
JACK_USAGE_maven="[-y]"
JACK_USAGE_cargo="[-y]"

. "$JACK_ROOT/lib/npm.sh"
. "$JACK_ROOT/lib/docker.sh"

_clean_simple() {
  local action="$1" extra="$2"
  shift 2
  [ "$extra" -eq 0 ] || die_usage "usage: $(jack_usage clean "$action")"
  require_cmd "$1"
  "$@"
}

_clean_require_os() {
  [ "${JACK_UNAME:-$(uname -s)}" = "$1" ] || die "$3 is for $2 only"
}

clean_pip() { _clean_simple pip $# pip cache purge; }
clean_yarn() { _clean_simple yarn $# yarn cache clean; }
clean_pnpm() { _clean_simple pnpm $# pnpm store prune; }
clean_composer() { _clean_simple composer $# composer clear-cache; }
clean_go() { _clean_simple go $# go clean -modcache; }

clean_npm() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage clean npm)"
  npm_cache_clear
}

clean_docker() {
  parse_yes_only "$(jack_usage clean docker)" "$@"
  if [ "$ASSUME_YES" -eq 1 ]; then
    docker_prune -y
  else
    docker_prune
  fi
}

clean_brew() {
  _clean_require_os Darwin macOS brew
  _clean_simple brew $# brew cleanup --prune=all
}

clean_xcode() {
  _clean_require_os Darwin macOS xcode
  parse_yes_only "$(jack_usage clean xcode)" "$@"
  local dir="${HOME:?}/Library/Developer/Xcode/DerivedData"
  if [ ! -d "$dir" ]; then
    echo "nothing to remove"
    return 0
  fi
  confirm_unless_yes "Delete $dir?" "$ASSUME_YES" || return 1
  rm -rf -- "$dir"
}

clean_apt() {
  _clean_require_os Linux Linux apt
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage clean apt)"
  require_root clean apt
  _clean_simple apt 0 apt clean
}

clean_journal() {
  _clean_require_os Linux Linux journal
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage clean journal)"
  require_root clean journal
  _clean_simple journal 0 journalctl --vacuum-size=100M
}

clean_snap() {
  _clean_require_os Linux Linux snap
  parse_yes_only "$(jack_usage clean snap)" "$@"
  require_root clean snap
  require_cmd snap
  local revs count name rev
  revs="$(snap list --all | awk '/disabled/ {print $1, $3}')"
  if [ -z "$revs" ]; then
    echo "nothing to remove"
    return 0
  fi
  count="$(printf '%s\n' "$revs" | wc -l | tr -d ' ')"
  confirm_unless_yes "Remove $count old snap revision(s)?" "$ASSUME_YES" || return 1
  while read -r name rev; do
    snap remove "$name" --revision="$rev"
  done <<< "$revs"
}

clean_gradle() {
  parse_yes_only "$(jack_usage clean gradle)" "$@"
  require_cmd gradle
  local dir="${HOME:?}/.gradle/caches"
  confirm_unless_yes "Stop the Gradle daemon and delete $dir?" "$ASSUME_YES" || return 1
  gradle --stop
  rm -rf -- "$dir"
}

clean_maven() {
  parse_yes_only "$(jack_usage clean maven)" "$@"
  local repo="${HOME:?}/.m2/repository" count
  if [ ! -d "$repo" ]; then
    echo "nothing to remove"
    return 0
  fi
  count="$(find "$repo" -name '*-SNAPSHOT' -mtime +90 -prune -print | wc -l | tr -d ' ')"
  if [ "$count" -eq 0 ]; then
    echo "nothing to remove"
    return 0
  fi
  confirm_unless_yes "Delete $count SNAPSHOT artifact(s) older than 90 days?" "$ASSUME_YES" || return 1
  find "$repo" -name '*-SNAPSHOT' -mtime +90 -prune -exec rm -rf {} +
}

clean_cargo() {
  parse_yes_only "$(jack_usage clean cargo)" "$@"
  require_cmd cargo
  confirm_unless_yes "Autoclean the cargo cache, installing cargo-cache if missing?" "$ASSUME_YES" || return 1
  cargo cache --version >/dev/null 2>&1 || cargo install cargo-cache || die "cargo install failed"
  cargo cache --autoclean
}
