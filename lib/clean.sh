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
JACK_DOC_list="Show every clean action and whether it can run on this machine"
JACK_USAGE_list=""
JACK_DOC_all="Run every available clean action except gradle, maven and cargo"
JACK_USAGE_all="[-y]"

. "$JACK_ROOT/lib/docker.sh"

_clean_simple() {
  local action="$1" extra="$2"
  shift 2
  [ "$extra" -eq 0 ] || die_usage "usage: $(jack_usage clean "$action")"
  require_cmd "$1"
  jack_spin "Cleaning $action" "$@"
}

_clean_require_os() {
  [ "${JACK_UNAME:-$(uname -s)}" = "$1" ] || die "$3 is for $2 only"
}

_clean_available() {
  local os="${JACK_UNAME:-$(uname -s)}"
  case "$1" in
    xcode) [ "$os" = Darwin ] && [ -d "${HOME:?}/Library/Developer/Xcode/DerivedData" ] ;;
    maven) [ -d "${HOME:?}/.m2/repository" ] ;;
    brew) [ "$os" = Darwin ] && command -v brew >/dev/null 2>&1 ;;
    apt|snap) [ "$os" = Linux ] && command -v "$1" >/dev/null 2>&1 ;;
    journal) [ "$os" = Linux ] && command -v journalctl >/dev/null 2>&1 ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}

_clean_needs_root() {
  case "$1" in
    apt|journal|snap) return 0 ;;
  esac
  return 1
}

clean_pip() { _clean_simple pip $# pip cache purge; }
clean_yarn() { _clean_simple yarn $# yarn cache clean; }
clean_pnpm() { _clean_simple pnpm $# pnpm store prune; }
clean_composer() { _clean_simple composer $# composer clear-cache; }
clean_go() { _clean_simple go $# go clean -modcache; }

clean_npm() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage clean npm)"
  require_cmd npm
  npm cache clear --force
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
  local listing revs count name rev failed=0
  listing="$(snap list --all)" || die "snap list failed"
  revs="$(printf '%s\n' "$listing" | awk '$NF ~ /(^|,)disabled(,|$)/ {print $1, $3}')"
  if [ -z "$revs" ]; then
    echo "nothing to remove"
    return 0
  fi
  count="$(printf '%s\n' "$revs" | wc -l | tr -d ' ')"
  confirm_unless_yes "Remove $count old snap revision(s)?" "$ASSUME_YES" || return 1
  while read -r name rev; do
    snap remove "$name" --revision="$rev" || failed=1
  done <<< "$revs"
  return "$failed"
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
  local repo="${HOME:?}/.m2/repository" dir old=()
  if [ ! -d "$repo" ]; then
    echo "nothing to remove"
    return 0
  fi
  while IFS= read -r -d '' dir; do
    if [ -z "$(find "$dir" -type f -mtime -90 -print -quit)" ]; then
      old+=("$dir")
    fi
  done < <(find "$repo" -type d -name '*-SNAPSHOT' -mtime +90 -prune -print0)
  if [ "${#old[@]}" -eq 0 ]; then
    echo "nothing to remove"
    return 0
  fi
  confirm_unless_yes "Delete ${#old[@]} SNAPSHOT artifact(s) older than 90 days?" "$ASSUME_YES" || return 1
  for dir in "${old[@]}"; do
    rm -rf -- "$dir"
  done
}

clean_cargo() {
  parse_yes_only "$(jack_usage clean cargo)" "$@"
  require_cmd cargo
  confirm_unless_yes "Autoclean the cargo cache, installing cargo-cache if missing?" "$ASSUME_YES" || return 1
  cargo cache --version >/dev/null 2>&1 || cargo install cargo-cache || die "cargo install failed"
  cargo cache --autoclean
}

clean_list() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage clean list)"
  local act ok
  echo "READY means the tool is installed and the action applies to this OS."
  echo
  printf '%-10s %-6s %s\n' ACTION READY DESCRIPTION
  for act in $(jack_actions clean); do
    case "$act" in list|all) continue ;; esac
    if _clean_available "$act"; then ok=yes; else ok=no; fi
    printf '%-10s %-6s %s\n' "$act" "$ok" "$(jack_meta clean DOC "$act")"
  done
}

clean_all() {
  parse_yes_only "$(jack_usage clean all)" "$@"
  local act todo="" args failed=""
  for act in $(jack_actions clean); do
    case "$act" in list|all|gradle|maven|cargo) continue ;; esac
    if ! _clean_available "$act"; then
      echo "skip $act, not available"
      continue
    fi
    if _clean_needs_root "$act" && [ "$(id -u)" -ne 0 ]; then
      echo "skip $act, needs root: sudo jack clean $act"
      continue
    fi
    todo="$todo $act"
  done
  if [ -z "$todo" ]; then
    echo "nothing to clean"
    return 0
  fi
  confirm_unless_yes "Run:$todo?" "$ASSUME_YES" || return 1
  for act in $todo; do
    echo "==> $act"
    args=""
    case "$act" in xcode|snap|docker) args="-y" ;; esac
    ( "clean_$act" $args ) || failed="$failed $act"
  done
  if [ -n "$failed" ]; then
    echo "failed:$failed" >&2
    return 1
  fi
}
