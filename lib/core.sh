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
  { [ $# -eq 1 ] && [ -n "$1" ]; } || die_usage "usage: jack $theme ssh-key <email>"
  require_cmd ssh-keygen
  local path="$HOME/.ssh/id_ed25519"
  [ ! -e "$path" ] || die "$path already exists"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  ssh-keygen -t ed25519 -C "$1" -f "$path"
  echo "public key: $path.pub"
}
