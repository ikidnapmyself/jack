JACK_DESC="Read-only memory and swap checks"
JACK_ABOUT="Shows how much RAM and swap your machine is using and which programs use the most. Everything here is read-only, nothing is changed or stopped. Swap in use is not a problem by itself. It matters when RAM is also nearly full, which is what the verdict in swap looks at."
JACK_DOC_swap="Show swap and RAM use with a verdict, plus the top swap users on Linux"
JACK_DOC_usage="Show total, used and available RAM"
JACK_DOC_top="List the programs using the most memory, count defaults to 10, max 50"
JACK_USAGE_swap=""
JACK_USAGE_usage=""
JACK_USAGE_top="[count]"
JACK_ASK_top="no"
JACK_INFO_swap="Shows swap used and total, RAM available and a verdict. ok means plenty of RAM and light swap. busy means half or more of swap is used. under pressure means less than 10 percent of RAM is available. On Linux it also lists the programs holding the most swap. macOS does not expose per-program swap, so use mem top there. Read-only."
JACK_INFO_usage="Shows total RAM, how much is in use and how much is available for new programs. Available counts memory the system can reclaim, so it is a better number than free. Read-only."
JACK_INFO_top="Ranks running programs by resident memory, the RAM each one holds right now. Shows pid so you can follow up with port kill or your own tools. Read-only."

_mem_os() {
  printf '%s\n' "${JACK_UNAME:-$(uname -s)}"
}

_mem_proc() {
  printf '%s\n' "${JACK_PROC_DIR:-/proc}"
}

_mem_stats() {
  local os total avail stotal sused level
  os="$(_mem_os)"
  case "$os" in
    Darwin)
      require_cmd sysctl
      total="$(sysctl -n hw.memsize 2>/dev/null)" || die "sysctl hw.memsize failed"
      level="$(sysctl -n kern.memorystatus_level 2>/dev/null)" || die "sysctl kern.memorystatus_level failed"
      total=$((total / 1024))
      avail=$((total * level / 100))
      read -r stotal sused <<< "$(sysctl -n vm.swapusage 2>/dev/null | awk '
        function kb(v) { n = v + 0; u = substr(v, length(v)); return n * (u == "G" ? 1048576 : u == "K" ? 1 : 1024) }
        { print int(kb($3)), int(kb($6)) }')"
      ;;
    Linux)
      local meminfo
      meminfo="$(_mem_proc)/meminfo"
      [ -r "$meminfo" ] || die "cannot read $meminfo"
      read -r total avail stotal sused <<< "$(awk '
        /^MemTotal:/ { t = $2 }
        /^MemAvailable:/ { a = $2 }
        /^MemFree:/ { f = $2 }
        /^SwapTotal:/ { st = $2 }
        /^SwapFree:/ { sf = $2 }
        END { print t, (a == "" ? f : a), st, st - sf }' "$meminfo")"
      ;;
    *) die "unsupported OS: $os" ;;
  esac
  printf '%s %s %s %s\n' "$total" "$avail" "$stotal" "$sused"
}

_mem_human() {
  awk -v kb="$1" 'BEGIN {
    if (kb >= 1048576) printf "%.1fG", kb / 1048576
    else if (kb >= 1024) printf "%.0fM", kb / 1024
    else printf "%dK", kb
  }'
}

_mem_pct() {
  if [ "$2" -le 0 ]; then echo 0; else echo $(($1 * 100 / $2)); fi
}

_mem_swap_users() {
  local status
  for status in "$(_mem_proc)"/[0-9]*/status; do
    [ -r "$status" ] && awk -v pid="${status%/status}" '
      /^Name:/ { name = $2 }
      /^VmSwap:/ && $2 > 0 { sub(/.*\//, "", pid); print $2, pid, name }' "$status"
  done 2>/dev/null | sort -rn | head -n 5
}

mem_swap() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage mem swap)"
  local total avail stotal sused spct apct verdict stats
  stats="$(_mem_stats)" || return 1
  read -r total avail stotal sused <<< "$stats"
  spct="$(_mem_pct "$sused" "$stotal")"
  apct="$(_mem_pct "$avail" "$total")"

  if [ "$apct" -lt 10 ]; then
    verdict="${RED}under pressure${RESET}"
  elif [ "$spct" -ge 50 ]; then
    verdict="${YELLOW}busy${RESET}"
  else
    verdict="${GREEN}ok${RESET}"
  fi

  if [ "$stotal" -le 0 ]; then
    printf '%-8s %s\n' Swap "none configured"
  else
    printf '%-8s %s used of %s (%s%%)\n' Swap "$(_mem_human "$sused")" "$(_mem_human "$stotal")" "$spct"
  fi
  printf '%-8s %s available of %s (%s%%)\n' RAM "$(_mem_human "$avail")" "$(_mem_human "$total")" "$apct"
  printf '%-8s %s\n' Verdict "$verdict"

  [ "$sused" -gt 0 ] || return 0
  if [ "$(_mem_os)" = Linux ]; then
    local users size pid name
    users="$(_mem_swap_users)"
    [ -z "$users" ] || {
      echo
      printf '%-8s %-8s %s\n' SWAP PID COMMAND
      while read -r size pid name; do
        printf '%-8s %-8s %s\n' "$(_mem_human "$size")" "$pid" "$name"
      done <<< "$users"
    }
  else
    echo
    echo "per-program swap is not exposed on macOS, try: jack mem top"
  fi
}

mem_usage() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage mem usage)"
  local total avail stotal sused used stats
  stats="$(_mem_stats)" || return 1
  read -r total avail stotal sused <<< "$stats"
  used=$((total - avail))
  printf '%-10s %s\n' Total "$(_mem_human "$total")"
  printf '%-10s %s (%s%%)\n' Used "$(_mem_human "$used")" "$(_mem_pct "$used" "$total")"
  printf '%-10s %s (%s%%)\n' Available "$(_mem_human "$avail")" "$(_mem_pct "$avail" "$total")"
}

mem_top() {
  require_cmd ps
  [ $# -le 1 ] || die_usage "usage: $(jack_usage mem top)"
  local count=10 rows rss pid cmd
  if [ $# -eq 1 ]; then
    case "$1" in
      ''|*[!0-9]*|0*|??????*) die_usage "invalid count: $1" ;;
    esac
    [ "$1" -le 50 ] || die_usage "invalid count: $1"
    count="$1"
  fi
  rows="$(ps -Ao rss=,pid=,comm= | sort -rn | head -n "$count")"
  printf '%-8s %-8s %s\n' RSS PID COMMAND
  while read -r rss pid cmd; do
    printf '%-8s %-8s %s\n' "$(_mem_human "$rss")" "$pid" "${cmd##*/}"
  done <<< "$rows"
}
