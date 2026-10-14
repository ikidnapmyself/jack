if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  RED=$'\033[31m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RESET=$'\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  RESET=''
fi

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

die_usage() {
  printf '%s\n' "$*" >&2
  exit 2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

confirm() {
  local reply
  printf '%s [y/N] ' "$1"
  read -r reply || return 1
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

confirm_unless_yes() {
  [ "$2" -eq 1 ] && return 0
  confirm "$1" || { echo "aborted" >&2; return 1; }
}

parse_yes_only() {
  local usage="$1" arg
  shift
  ASSUME_YES=0
  for arg in "$@"; do
    case "$arg" in
      -y) ASSUME_YES=1 ;;
      *) die_usage "usage: $usage" ;;
    esac
  done
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "needs root, run: sudo jack $*"
}

validate_port() {
  case "$1" in
    ''|*[!0-9]*|0*|??????*) die_usage "invalid port: $1" ;;
  esac
  if [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
    die_usage "invalid port: $1"
  fi
}

ssh_keygen_for() {
  local theme="$1"
  shift
  { [ $# -eq 1 ] && [ -n "$1" ]; } || die_usage "usage: $(jack_usage "$theme" ssh-key)"
  require_cmd ssh-keygen
  local path="$HOME/.ssh/id_ed25519"
  [ ! -e "$path" ] || die "$path already exists"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$1" -f "$path"
  echo "public key: $path.pub"
}

jack_themes() {
  local file name
  for file in "$JACK_ROOT"/lib/*.sh; do
    name="$(basename "$file" .sh)"
    [ "$name" = core ] || echo "$name"
  done
}

jack_actions() {
  sed -n "s/^$1_\([a-z_]*\)()[[:space:]]*{.*/\1/p" "$JACK_ROOT/lib/$1.sh"
}

jack_meta() {
  sed -n "s/^JACK_$2_$3=\"\(.*\)\"\$/\1/p" "$JACK_ROOT/lib/$1.sh" | head -n 1
}

jack_usage() {
  local theme="$1" args
  args="$(jack_meta "$theme" USAGE "$(printf %s "$2" | tr - _)")"
  printf 'jack %s %s%s\n' "$theme" "$(printf %s "$2" | tr _ -)" "${args:+ $args}"
}

jack_desc() {
  sed -n 's/^JACK_DESC="\(.*\)"$/\1/p' "$JACK_ROOT/lib/$1.sh" | head -n 1
}

jack_print_actions() {
  local act
  for act in $(jack_actions "$1"); do
    printf '  %-18s %s\n' "$(printf %s "$act" | tr _ -)" "$(jack_meta "$1" DOC "$act")"
  done
}

_jack_candidate() {
  if [ "$JACK_COMPLETE_DESC" -eq 1 ]; then
    printf '%s:%s\n' "$1" "$2"
  else
    printf '%s\n' "$1"
  fi
}

jack_complete() {
  JACK_COMPLETE_DESC=0
  if [ "${1:-}" = --desc ]; then
    JACK_COMPLETE_DESC=1
    shift
  fi
  local name act
  case $# in
    0|1)
      for name in $(jack_themes); do
        _jack_candidate "$name" "$(jack_desc "$name")"
      done
      _jack_candidate help "Show help"
      ;;
    2)
      case "$1" in
        ''|*[!a-z]*) return 0 ;;
      esac
      { [ "$1" != core ] && [ -f "$JACK_ROOT/lib/$1.sh" ]; } || return 0
      for act in $(jack_actions "$1"); do
        _jack_candidate "$(printf %s "$act" | tr _ -)" "$(jack_meta "$1" DOC "$act")"
      done
      _jack_candidate help "Show help"
      ;;
  esac
  return 0
}
