JACK_DESC="Ubuntu chores"
JACK_DOC_flush_dns="Restart named and nscd to flush DNS caches, needs root"
JACK_DOC_ports="List listening TCP ports with owning processes"
JACK_DOC_port_test="Check whether a host accepts TCP connections on a port"
JACK_DOC_count="Count files under a directory"
JACK_DOC_mysql_config="Show where MySQL looks for option files"
JACK_DOC_ssh_key="Generate an ed25519 SSH key for an email"

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
