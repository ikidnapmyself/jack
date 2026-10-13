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
