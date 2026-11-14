JACK_DESC="List crontab jobs with next runs and logs"
JACK_ABOUT="Read-only view of your scheduled jobs, the user crontab. Shows what runs and when, the next run times, and where each job writes its output. It cannot add, edit or remove jobs."
JACK_DOC_list="List crontab jobs with next run times, count is how many upcoming runs per job (default 1, max 50)"
JACK_DOC_logs="Without n, list jobs that have a log file. With n, tail that job, lines defaults to 20"
JACK_USAGE_list="[count]"
JACK_USAGE_logs="[n] [lines]"
JACK_INFO_list="Shows each crontab job with its schedule, its next run times and its command. The optional count sets how many upcoming runs to show per job, default 1, max 50. Read-only."
JACK_INFO_logs="Without a job number, lists the jobs whose log file exists. With a number from list, shows the last lines of that job's log, default 20. If the job has no log file it falls back to the system cron log. Read-only."

_cron_days_from_civil() {
  local y=$1 m=$2 d=$3 era yoe doy doe
  [ "$m" -gt 2 ] || y=$((y - 1))
  era=$((y / 400))
  yoe=$((y - era * 400))
  if [ "$m" -gt 2 ]; then doy=$(((153 * (m - 3) + 2) / 5 + d - 1)); else doy=$(((153 * (m + 9) + 2) / 5 + d - 1)); fi
  doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
  echo $((era * 146097 + doe - 719468))
}

_cron_dow() {
  echo $((($(_cron_days_from_civil "$1" "$2" "$3") + 4) % 7))
}

_cron_dim() {
  case "$2" in
    1|3|5|7|8|10|12) echo 31 ;;
    4|6|9|11) echo 30 ;;
    *)
      if [ $(($1 % 4)) -eq 0 ] && { [ $(($1 % 100)) -ne 0 ] || [ $(($1 % 400)) -eq 0 ]; }; then
        echo 29
      else
        echo 28
      fi
      ;;
  esac
}

_cron_num() {
  local tok names="$2" base="$3" i=0 n
  tok="$(printf %s "$1" | tr 'A-Z' 'a-z')"
  case "$tok" in
    ''|*[!0-9]*)
      for n in $names; do
        if [ "$n" = "$tok" ]; then echo $((i + base)); return 0; fi
        i=$((i + 1))
      done
      return 1
      ;;
  esac
  case "$tok" in ??????*) return 1 ;; esac
  echo $((10#$tok))
}

_cron_expand() {
  local spec="$1" min="$2" max="$3" names="${4:-}" out=" " part range step lo hi i v
  local base=$min
  local -a parts
  IFS=, read -r -a parts <<< "$spec"
  [ "${#parts[@]}" -gt 0 ] || return 1
  for part in "${parts[@]}"; do
    step=1
    range="$part"
    case "$part" in
      */*)
        step="${part#*/}"
        range="${part%/*}"
        case "$step" in ''|*[!0-9]*|0*) return 1 ;; esac
        ;;
    esac
    case "$range" in
      '*') lo=$min; hi=$max ;;
      *-*)
        lo="$(_cron_num "${range%-*}" "$names" "$base")" || return 1
        hi="$(_cron_num "${range#*-}" "$names" "$base")" || return 1
        ;;
      *)
        lo="$(_cron_num "$range" "$names" "$base")" || return 1
        hi=$lo
        case "$part" in */*) hi=$max ;; esac
        ;;
    esac
    [ "$lo" -ge "$min" ] && [ "$hi" -le "$max" ] && [ "$lo" -le "$hi" ] || return 1
    i=$lo
    while [ "$i" -le "$hi" ]; do
      v=$i
      [ "$max" -ne 7 ] || [ "$v" -ne 7 ] || v=0
      case "$out" in *" $v "*) ;; *) out="$out$v " ;; esac
      i=$((i + step))
    done
  done
  printf '%s\n' "$out"
}

_cron_sorted() {
  printf '%s\n' $1 | sort -n | tr '\n' ' '
}

_cron_macro() {
  case "$1" in
    @yearly|@annually) echo "0 0 1 1 *" ;;
    @monthly) echo "0 0 1 * *" ;;
    @weekly) echo "0 0 * * 0" ;;
    @daily|@midnight) echo "0 0 * * *" ;;
    @hourly) echo "0 * * * *" ;;
    *) return 1 ;;
  esac
}

_cron_now() {
  if [ -n "${JACK_CRON_NOW:-}" ]; then
    printf '%s\n' "$JACK_CRON_NOW" | tr -c '0-9\n' ' '
  else
    date '+%Y %m %d %H %M'
  fi
}

_cron_jobs() {
  local line first rest sched
  crontab -l 2>/dev/null | while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in
      ''|'#'*) continue ;;
      [A-Za-z_]*=*) continue ;;
    esac
    first="${line%%[[:space:]]*}"
    case "$first" in
      @reboot)
        rest="${line#"$first"}"
        printf '%s\t%s\n' "@reboot" "${rest#"${rest%%[![:space:]]*}"}"
        ;;
      @*)
        sched="$(_cron_macro "$first")" || { printf '%s\t%s\n' "$first" "-"; continue; }
        rest="${line#"$first"}"
        printf '%s\t%s\n' "$sched" "${rest#"${rest%%[![:space:]]*}"}"
        ;;
      *)
        local m h dom mon dow cmd
        read -r m h dom mon dow cmd <<< "$line"
        printf '%s\t%s\n' "$m $h $dom $mon $dow" "$cmd"
        ;;
    esac
  done
}

_cron_job() {
  _cron_jobs | sed -n "${1}p"
}

_cron_next() {
  local sched="$1" count="$2"
  local m h dom mon dow
  read -r m h dom mon dow <<< "$sched"
  local mset hset dset nset wset
  mset="$(_cron_expand "$m" 0 59)" || return 1
  hset="$(_cron_expand "$h" 0 23)" || return 1
  dset="$(_cron_expand "$dom" 1 31)" || return 1
  nset="$(_cron_expand "$mon" 1 12 "jan feb mar apr may jun jul aug sep oct nov dec")" || return 1
  wset="$(_cron_expand "$dow" 0 7 "sun mon tue wed thu fri sat")" || return 1
  mset="$(_cron_sorted "$mset")"
  hset="$(_cron_sorted "$hset")"

  local dstar=0 wstar=0
  case "$dom" in '*'*) dstar=1 ;; esac
  case "$dow" in '*'*) wstar=1 ;; esac

  local y mo d H M startmin first=1 days=0 wd ok hh mm names=(Sun Mon Tue Wed Thu Fri Sat)
  read -r y mo d H M <<< "$(_cron_now)"
  y=$((10#$y)); mo=$((10#$mo)); d=$((10#$d))
  startmin=$((10#$H * 60 + 10#$M + 1))

  while [ "$days" -lt 1500 ] && [ "$count" -gt 0 ]; do
    ok=0
    case "$nset" in *" $mo "*) ok=1 ;; esac
    if [ "$ok" -eq 1 ]; then
      wd="$(_cron_dow "$y" "$mo" "$d")"
      local dm=0 wm=0
      case "$dset" in *" $d "*) dm=1 ;; esac
      case "$wset" in *" $wd "*) wm=1 ;; esac
      if [ "$dstar" -eq 1 ] && [ "$wstar" -eq 1 ]; then ok=1
      elif [ "$dstar" -eq 1 ]; then ok=$wm
      elif [ "$wstar" -eq 1 ]; then ok=$dm
      elif [ "$dm" -eq 1 ] || [ "$wm" -eq 1 ]; then ok=1
      else ok=0
      fi
    fi
    if [ "$ok" -eq 1 ]; then
      for hh in $hset; do
        for mm in $mset; do
          if [ "$first" -eq 1 ] && [ $((hh * 60 + mm)) -lt "$startmin" ]; then continue; fi
          [ "$count" -gt 0 ] || break 2
          printf '%s %04d-%02d-%02d %02d:%02d\n' "${names[$wd]}" "$y" "$mo" "$d" "$hh" "$mm"
          count=$((count - 1))
        done
      done
    fi
    first=0
    days=$((days + 1))
    d=$((d + 1))
    if [ "$d" -gt "$(_cron_dim "$y" "$mo")" ]; then
      d=1
      mo=$((mo + 1))
      if [ "$mo" -gt 12 ]; then mo=1; y=$((y + 1)); fi
    fi
  done
}

_cron_positive() {
  case "$1" in
    ''|*[!0-9]*|0*|??????*) return 1 ;;
  esac
}

cron_list() {
  require_cmd crontab
  [ $# -le 1 ] || die_usage "usage: $(jack_usage cron list)"
  local count=1
  if [ $# -eq 1 ]; then
    _cron_positive "$1" && [ "$1" -le 50 ] || die_usage "invalid count: $1"
    count="$1"
  fi

  local jobs n=0 sched cmd next line first
  jobs="$(_cron_jobs)"
  if [ -z "$jobs" ]; then
    echo "no cron jobs" >&2
    return 1
  fi

  printf '%-3s %-15s %-22s %s\n' '#' SCHEDULE NEXT COMMAND
  while IFS=$'\t' read -r sched cmd; do
    n=$((n + 1))
    if [ "$sched" = "@reboot" ]; then
      printf '%-3s %-15s %-22s %s\n' "$n" "@reboot" "at boot" "$cmd"
      continue
    fi
    if ! next="$(_cron_next "$sched" "$count")"; then
      printf '%-3s %-15s %-22s %s\n' "$n" "${sched// /_}" "${RED}invalid schedule${RESET}" "$cmd"
      continue
    fi
    if [ -z "$next" ]; then
      printf '%-3s %-15s %-22s %s\n' "$n" "${sched// /_}" "never" "$cmd"
      continue
    fi
    first=1
    while IFS= read -r line; do
      if [ "$first" -eq 1 ]; then
        printf '%-3s %-15s %-22s %s\n' "$n" "${sched// /_}" "$line" "$cmd"
        first=0
      else
        printf '%-3s %-15s %s\n' '' '' "$line"
      fi
    done <<< "$next"
  done <<< "$jobs"
}

_cron_logfile() {
  local tok prev="" file="" path
  set -f
  for tok in $1; do
    case "$tok" in '#'*) break ;; esac
    path=""
    case "$prev" in
      '>'|'>>') path="$tok" ;;
    esac
    case "$tok" in
      '>>'|'>') ;;
      '>>'?*) path="${tok#>>}" ;;
      '>'?*) path="${tok#>}" ;;
    esac
    case "$path" in
      ''|'&'*|/dev/null) ;;
      *) file="$path" ;;
    esac
    prev="$tok"
  done
  set +f
  file="${file#[\"\']}"
  file="${file%[\"\']}"
  case "$file" in
    '~'/*) file="$HOME/${file#\~/}" ;;
    '$HOME'/*) file="$HOME/${file#\$HOME/}" ;;
    '${HOME}'/*) file="$HOME/${file#\$\{HOME\}/}" ;;
    '') return 1 ;;
    /*) ;;
    *) file="$HOME/$file" ;;
  esac
  printf '%s\n' "$file"
}

_cron_syslog() {
  local needle="$1" lines="$2" n="$3" src out found=0
  case "${JACK_UNAME:-$(uname -s)}" in
    Darwin)
      out="$(log show --last 1d --style compact --predicate 'process == "cron"' 2>/dev/null | grep -F -- "$needle")"
      if [ -n "$out" ]; then printf '%s\n' "$out" | tail -n "$lines"; return 0; fi
      echo "no matching entries in the macOS log" >&2
      return 1
      ;;
  esac
  if command -v journalctl >/dev/null 2>&1; then
    out="$(journalctl -t CRON -t crond --no-pager -n 5000 2>/dev/null | grep -F -- "$needle")"
    if [ -n "$out" ]; then printf '%s\n' "$out" | tail -n "$lines"; return 0; fi
  fi
  for src in /var/log/syslog /var/log/cron /var/log/cron.log; do
    [ -e "$src" ] || continue
    found=1
    if [ ! -r "$src" ]; then
      echo "$src is not readable, try: sudo jack cron logs $n $lines" >&2
      return 1
    fi
    out="$(grep -F -- "$needle" "$src")"
    if [ -n "$out" ]; then printf '%s\n' "$out" | tail -n "$lines"; return 0; fi
  done
  [ "$found" -eq 1 ] || echo "no system cron log found" >&2
  echo "no matching entries in the system log" >&2
  return 1
}

cron_logs() {
  require_cmd crontab
  [ $# -le 2 ] || die_usage "usage: $(jack_usage cron logs)"

  if [ $# -eq 0 ]; then
    local jobs n=0 sched cmd file shown=0
    jobs="$(_cron_jobs)"
    if [ -z "$jobs" ]; then
      echo "no cron jobs" >&2
      return 1
    fi
    while IFS=$'\t' read -r sched cmd; do
      n=$((n + 1))
      file="$(_cron_logfile "$cmd")" && [ -f "$file" ] || continue
      if [ "$shown" -eq 0 ]; then printf '%-3s %-40s %s\n' '#' LOG COMMAND; fi
      shown=$((shown + 1))
      printf '%-3s %-40s %s\n' "$n" "$file" "$cmd"
    done <<< "$jobs"
    if [ "$shown" -eq 0 ]; then
      echo "no job has a log file" >&2
      return 1
    fi
    return 0
  fi

  local lines=20 job sched cmd file
  _cron_positive "$1" || die_usage "invalid job number: $1"
  if [ $# -eq 2 ]; then
    _cron_positive "$2" || die_usage "invalid line count: $2"
    lines="$2"
  fi
  job="$(_cron_job "$1")"
  [ -n "$job" ] || { echo "no cron job $1" >&2; return 1; }
  IFS=$'\t' read -r sched cmd <<< "$job"

  if file="$(_cron_logfile "$cmd")" && [ -f "$file" ]; then
    if [ ! -r "$file" ]; then
      echo "$file is not readable, try: sudo jack cron logs $1 $lines" >&2
      return 1
    fi
    tail -n "$lines" "$file"
    return
  fi

  echo "no job log file, showing the system log" >&2
  _cron_syslog "${cmd:0:40}" "$lines" "$1"
}
