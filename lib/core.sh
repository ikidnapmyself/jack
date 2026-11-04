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

JACK_VERSION="0.1.0"
JACK_TUIN_VERSION="0.2.0"
JACK_TUIN_SHA256="7f69fb0edf827ac0e764cee044c14ed5628add59837a97d3e6daf0fd7b73a0e0"
JACK_TUIN_DEFAULT_FILE="$JACK_ROOT/lib/vendor/tuin.sh"
JACK_TUIN_FILE="${JACK_TUIN_FILE:-$JACK_TUIN_DEFAULT_FILE}"
JACK_TUIN_STATE="${JACK_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/jack}/tuin"
JACK_TUIN_ON=0

jack_tuin_state() {
  cat "$JACK_TUIN_STATE" 2>/dev/null
}

jack_tuin_set() {
  mkdir -p "$(dirname "$JACK_TUIN_STATE")" && printf '%s\n' "$1" > "$JACK_TUIN_STATE"
}

jack_sha256() {
  shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1 | grep . || sha256sum "$1" 2>/dev/null | cut -d' ' -f1
}

jack_tuin_load() {
  [ "$(jack_tuin_state)" = on ] && [ -f "$JACK_TUIN_FILE" ] || return 0
  if [ "$JACK_TUIN_FILE" != "$JACK_TUIN_DEFAULT_FILE" ]; then
    if [ "$(id -u)" = 0 ]; then
      echo "warning: ignoring JACK_TUIN_FILE override while running as root" >&2
      return 0
    fi
  elif [ "$(jack_sha256 "$JACK_TUIN_FILE")" != "$JACK_TUIN_SHA256" ]; then
    echo "warning: tuin checksum mismatch, not loading $JACK_TUIN_FILE" >&2
    return 0
  fi
  . "$JACK_TUIN_FILE" && JACK_TUIN_ON=1
  return 0
}

jack_tuin_install() {
  command -v curl >/dev/null 2>&1 || { echo "error: curl is needed to download tuin" >&2; return 1; }
  local tmp sum
  tmp="$(mktemp)" || return 1
  if ! curl -fsSL "https://raw.githubusercontent.com/ikidnapmyself/tuin/v$JACK_TUIN_VERSION/tuin.sh" -o "$tmp"; then
    rm -f "$tmp"
    echo "error: tuin download failed" >&2
    return 1
  fi
  sum="$(jack_sha256 "$tmp")"
  if [ "$sum" != "$JACK_TUIN_SHA256" ]; then
    rm -f "$tmp"
    echo "error: tuin checksum mismatch" >&2
    return 1
  fi
  mkdir -p "$(dirname "$JACK_TUIN_FILE")" && mv "$tmp" "$JACK_TUIN_FILE"
}

jack_tuin_offer() {
  [ -t 0 ] && [ -t 1 ] || return 0
  [ -z "$(jack_tuin_state)" ] || return 0
  if confirm "Enable the tuin UI (menus, spinners, prompts)? Downloads tuin v$JACK_TUIN_VERSION."; then
    if jack_tuin_install; then
      jack_tuin_set on
      jack_tuin_load
    fi
  else
    jack_tuin_set off
  fi
}

jack_spin() {
  local label="$1"
  shift
  if [ "$JACK_TUIN_ON" -eq 1 ]; then
    tuin_spin "$label" -- "$@"
  else
    "$@"
  fi
}

confirm() {
  local reply
  if [ "$JACK_TUIN_ON" -eq 1 ]; then
    tuin_confirm "$1" n
    return
  fi
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
  { [ $# -ge 1 ] && [ $# -le 2 ] && [ -n "$1" ]; } || die_usage "usage: $(jack_usage "$theme" ssh-key)"
  require_cmd ssh-keygen
  local path="${2:-$HOME/.ssh/id_ed25519}"
  case "$path" in
    -*) die_usage "invalid path: $path" ;;
  esac
  [ ! -e "$path" ] || die "$path already exists"
  mkdir -p "$(dirname "$path")"
  [ -n "${2:-}" ] || chmod 700 "$HOME/.ssh"
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

jack_theme_visible() {
  local os
  os="$(sed -n 's/^JACK_OS="\(.*\)"$/\1/p' "$JACK_ROOT/lib/$1.sh" | head -n 1)"
  [ -z "$os" ] || [ "$os" = "${JACK_UNAME:-$(uname -s)}" ]
}

jack_visible_themes() {
  local name
  for name in $(jack_themes); do
    ! jack_theme_visible "$name" || echo "$name"
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
      for name in $(jack_visible_themes); do
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

jack_tuin_load
