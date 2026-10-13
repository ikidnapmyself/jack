JACK_DESC="List and kill processes on TCP ports"

_port_validate() {
  case "$1" in
    ''|*[!0-9]*|0*|??????*) die_usage "invalid port: $1" ;;
  esac
  if [ "$1" -lt 1 ] || [ "$1" -gt 65535 ]; then
    die_usage "invalid port: $1"
  fi
}

_port_rows() {
  lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk -v want="${1:-}" '
    NR > 1 {
      p = $(NF - 1)
      sub(/.*:/, "", p)
      if (want == "" || p == want) print p, $2, $3
    }' | sort -n -u -k1,1 -k2,2
}

_port_cmdline() {
  ps -o command= -p "$1" 2>/dev/null
}

port_list() {
  require_cmd lsof
  if [ $# -gt 0 ]; then
    _port_validate "$1"
  fi

  local rows port pid user
  rows="$(_port_rows "${1:-}")"
  if [ -z "$rows" ]; then
    echo "no TCP listeners${1:+ on port $1}" >&2
    return 1
  fi

  printf '%-6s %-7s %-12s %s\n' PORT PID USER COMMAND
  while read -r port pid user; do
    printf '%-6s %-7s %-12s %s\n' "$port" "$pid" "$user" "$(_port_cmdline "$pid")"
  done <<< "$rows"
}
