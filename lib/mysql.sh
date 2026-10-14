JACK_DESC="MySQL chores"
JACK_DOC_dump="Dump a database or chosen tables to a file with mysqldump"
JACK_ALIAS_dump="mydump"

mysql_dump() {
  local usage="usage: jack mysql dump <db> <file> [table...] [-u user]"
  local user="${USER:-root}" n=$#
  while [ "$n" -gt 0 ]; do
    case "$1" in
      -u)
        [ $# -ge 2 ] || die_usage "$usage"
        user="$2"
        shift 2
        n=$((n - 2))
        ;;
      -*) die_usage "$usage" ;;
      *)
        set -- "$@" "$1"
        shift
        n=$((n - 1))
        ;;
    esac
  done
  [ $# -ge 2 ] || die_usage "$usage"
  local db="$1" file="$2"
  shift 2
  case "$db" in
    ''|-*|*[!A-Za-z0-9_.$-]*) die_usage "invalid database: $db" ;;
  esac
  require_cmd mysqldump
  [ ! -e "$file" ] || die "$file exists"
  mysqldump -u "$user" -p "$db" "$@" > "$file" || { rm -f "$file"; die "mysqldump failed"; }
}
