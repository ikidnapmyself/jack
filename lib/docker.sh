JACK_DESC="Docker and docker-compose chores"
JACK_DOC_stop="Stop all running containers"
JACK_DOC_rm="Remove all exited containers"
JACK_DOC_prune="Remove unused containers, networks, images and cache, --volumes adds volumes"
JACK_DOC_ps="Show this project's compose services"
JACK_DOC_restart="Restart one compose service"
JACK_USAGE_stop="[-y]"
JACK_USAGE_rm="[-y]"
JACK_USAGE_prune="[--volumes] [-y]"
JACK_USAGE_ps=""
JACK_USAGE_restart="<service>"

docker_stop() {
  parse_yes_only "$(jack_usage docker stop)" "$@"
  require_cmd docker
  local ids count
  ids="$(docker ps -q)" || die "docker ps failed"
  if [ -z "$ids" ]; then
    echo "nothing to stop"
    return 0
  fi
  count="$(printf '%s\n' "$ids" | wc -l | tr -d ' ')"
  confirm_unless_yes "Stop $count container(s)?" "$ASSUME_YES" || return 1
  docker stop $ids
}

docker_rm() {
  parse_yes_only "$(jack_usage docker rm)" "$@"
  require_cmd docker
  local ids count
  ids="$(docker ps -aq -f status=exited)" || die "docker ps failed"
  if [ -z "$ids" ]; then
    echo "nothing to remove"
    return 0
  fi
  count="$(printf '%s\n' "$ids" | wc -l | tr -d ' ')"
  confirm_unless_yes "Remove $count container(s)?" "$ASSUME_YES" || return 1
  docker rm $ids
}

docker_prune() {
  local volumes="" assume_yes=0 arg
  for arg in "$@"; do
    case "$arg" in
      -y) assume_yes=1 ;;
      --volumes) volumes="--volumes" ;;
      *) die_usage "usage: $(jack_usage docker prune)" ;;
    esac
  done
  require_cmd docker
  confirm_unless_yes "Prune unused Docker objects${volumes:+ including volumes}?" "$assume_yes" || return 1
  jack_spin "Pruning Docker" docker system prune -f $volumes
}

docker_ps() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage docker ps)"
  require_cmd docker-compose
  docker-compose ps
}

_docker_pick_restart() {
  command -v docker-compose >/dev/null 2>&1 || return 0
  docker-compose config --services 2>/dev/null
}

docker_restart() {
  [ $# -eq 1 ] || die_usage "usage: $(jack_usage docker restart)"
  case "$1" in
    ''|-*|*[!A-Za-z0-9_.-]*) die_usage "invalid service: $1" ;;
  esac
  require_cmd docker-compose
  docker-compose restart "$1"
}
