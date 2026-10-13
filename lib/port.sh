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

_port_alive() {
  local state
  state="$(ps -o stat= -p "$1" 2>/dev/null)"
  [ -n "$state" ] && [ "${state#Z}" = "$state" ]
}

_port_terminate() {
  local pid="$1" err i

  if ! err="$(kill -TERM "$pid" 2>&1)"; then
    if _port_alive "$pid"; then
      echo "${RED}$pid: $err${RESET}" >&2
      return 2
    fi
    echo "$pid already gone"
    return 0
  fi

  for i in 1 2 3 4 5 6; do
    if ! _port_alive "$pid"; then
      echo "${GREEN}$pid terminated${RESET}"
      return 0
    fi
    sleep 0.5
  done

  kill -KILL "$pid" 2>/dev/null
  for i in 1 2 3 4 5; do
    _port_alive "$pid" || break
    sleep 0.2
  done
  if _port_alive "$pid"; then
    echo "${RED}$pid survived SIGKILL${RESET}" >&2
    return 1
  fi
  echo "${YELLOW}$pid killed with SIGKILL${RESET}"
}

port_kill() {
  require_cmd lsof

  local port="" assume_yes=0 arg
  for arg in "$@"; do
    case "$arg" in
      -y) assume_yes=1 ;;
      -*) die_usage "unknown option: $arg" ;;
      *)
        [ -z "$port" ] || die_usage "usage: jack port kill <port> [-y]"
        port="$arg"
        ;;
    esac
  done
  [ -n "$port" ] || die_usage "usage: jack port kill <port> [-y]"
  _port_validate "$port"

  local pids pid count
  pids="$(_port_rows "$port" | awk '{print $2}' | sort -un)"
  if [ -z "$pids" ]; then
    echo "nothing listening on port $port" >&2
    return 1
  fi

  for pid in $pids; do
    printf '%s  %s  %s\n' "$pid" "$(ps -o user= -p "$pid" | tr -d ' ')" "$(_port_cmdline "$pid")"
  done

  count="$(printf '%s\n' "$pids" | wc -l | tr -d ' ')"
  if [ "$assume_yes" -eq 0 ]; then
    confirm "Kill $count process(es)?" || { echo "aborted" >&2; return 1; }
  fi

  local fresh live=""
  fresh="$(_port_rows "$port" | awk '{print $2}' | sort -un)"
  for pid in $pids; do
    case " $(echo $fresh) " in
      *" $pid "*) live="$live $pid" ;;
    esac
  done
  if [ -z "$live" ]; then
    echo "nothing listening on port $port" >&2
    return 1
  fi

  local rc failed=0 denied=0
  for pid in $live; do
    rc=0
    _port_terminate "$pid" || rc=$?
    case "$rc" in
      0) ;;
      2) failed=1; denied=1 ;;
      *) failed=1 ;;
    esac
  done

  if [ "$denied" -eq 1 ]; then
    echo "permission denied, try: sudo jack port kill $port -y" >&2
  fi
  return "$failed"
}
