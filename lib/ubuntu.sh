JACK_DESC="Ubuntu chores"
JACK_DOC_flush_dns="Restart named and nscd to flush DNS caches, needs root"
JACK_DOC_ports="List listening TCP ports with owning processes"
JACK_DOC_port_test="Check whether a host accepts TCP connections on a port"
JACK_DOC_count="Count files under a directory"
JACK_DOC_mysql_config="Show where MySQL looks for option files"
JACK_DOC_ssh_key="Generate an ed25519 SSH key for an email"
JACK_DOC_big_files="List files over a size such as 500k, 10M or 1G"
JACK_DOC_big_files_delete="Delete files over a size after showing how many match"
JACK_DOC_mount="Mount a device at a target directory, needs root"

ubuntu_flush_dns() {
  [ $# -eq 0 ] || die_usage "usage: jack ubuntu flush-dns"
  require_root ubuntu flush-dns
  require_cmd service
  service named restart
  service nscd restart
}

ubuntu_ports() {
  [ $# -eq 0 ] || die_usage "usage: jack ubuntu ports"
  require_cmd ss
  ss -lntp
}

ubuntu_port_test() {
  [ $# -eq 2 ] || die_usage "usage: jack ubuntu port-test <host> <port>"
  case "$1" in
    ''|-*|*[!A-Za-z0-9.:-]*) die_usage "invalid host: $1" ;;
  esac
  validate_port "$2"
  require_cmd nc
  if nc -z -w 3 "$1" "$2"; then
    echo "${GREEN}$1:$2 open${RESET}"
  else
    echo "${RED}$1:$2 closed${RESET}" >&2
    return 1
  fi
}

ubuntu_count() {
  [ $# -le 1 ] || die_usage "usage: jack ubuntu count [dir]"
  local dir="${1:-.}"
  [ -d "$dir" ] || die_usage "not a directory: $dir"
  find "$dir" -type f | wc -l | tr -d ' '
}

ubuntu_mysql_config() {
  [ $# -eq 0 ] || die_usage "usage: jack ubuntu mysql-config"
  require_cmd mysql
  mysql --verbose --help | grep -A 1 "Default options"
}

ubuntu_ssh_key() {
  ssh_keygen_for ubuntu "$@"
}

_ubuntu_validate_size() {
  case "$1" in
    ''|*[!0-9kMGcb]*|*[kMGcb]?*|[kMGcb]*) die_usage "invalid size: $1" ;;
  esac
}

_ubuntu_big_matches() {
  find "$2" -type f -size +"$1"
}

ubuntu_big_files() {
  { [ $# -ge 1 ] && [ $# -le 2 ]; } || die_usage "usage: jack ubuntu big-files <size> [dir]"
  _ubuntu_validate_size "$1"
  local dir="${2:-.}" matches
  [ -d "$dir" ] || die_usage "not a directory: $dir"
  matches="$(_ubuntu_big_matches "$1" "$dir")"
  if [ -z "$matches" ]; then
    echo "no files over $1 in $dir" >&2
    return 1
  fi
  printf '%s\n' "$matches"
}

ubuntu_big_files_delete() {
  local usage="usage: jack ubuntu big-files-delete <size> [dir] [-y]"
  local assume_yes=0 n=$#
  while [ "$n" -gt 0 ]; do
    case "$1" in
      -y) assume_yes=1; shift ;;
      -*) die_usage "$usage" ;;
      *) set -- "$@" "$1"; shift ;;
    esac
    n=$((n - 1))
  done
  { [ $# -ge 1 ] && [ $# -le 2 ]; } || die_usage "$usage"
  _ubuntu_validate_size "$1"
  local dir="${2:-.}" matches count
  [ -d "$dir" ] || die_usage "not a directory: $dir"
  matches="$(_ubuntu_big_matches "$1" "$dir")"
  if [ -z "$matches" ]; then
    echo "no files over $1 in $dir" >&2
    return 1
  fi
  printf '%s\n' "$matches"
  count="$(printf '%s\n' "$matches" | wc -l | tr -d ' ')"
  confirm_unless_yes "Delete $count file(s) over $1 in $dir?" "$assume_yes" || return 1
  find "$dir" -type f -size +"$1" -delete
}

ubuntu_mount() {
  [ $# -eq 2 ] || die_usage "usage: jack ubuntu mount <device> <target>"
  case "$1" in
    /dev/?*) ;;
    *) die_usage "invalid device: $1" ;;
  esac
  [ -d "$2" ] || die_usage "not a directory: $2"
  require_root ubuntu mount "$@"
  require_cmd mount
  mount "$1" "$2"
}
