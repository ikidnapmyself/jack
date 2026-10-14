JACK_DESC="Cache and disk cleanup"
JACK_DOC_pip="Purge the pip cache"
JACK_DOC_yarn="Clean the Yarn cache"
JACK_DOC_pnpm="Prune the pnpm store"
JACK_DOC_composer="Clear the Composer cache"
JACK_DOC_go="Clean the Go module cache"
JACK_DOC_npm="Force-clear the npm cache"
JACK_DOC_docker="Remove unused Docker containers, networks, images and cache"
JACK_USAGE_pip=""
JACK_USAGE_yarn=""
JACK_USAGE_pnpm=""
JACK_USAGE_composer=""
JACK_USAGE_go=""
JACK_USAGE_npm=""
JACK_USAGE_docker="[-y]"

. "$JACK_ROOT/lib/npm.sh"
. "$JACK_ROOT/lib/docker.sh"

_clean_simple() {
  local action="$1" extra="$2"
  shift 2
  [ "$extra" -eq 0 ] || die_usage "usage: $(jack_usage clean "$action")"
  require_cmd "$1"
  "$@"
}

clean_pip() { _clean_simple pip $# pip cache purge; }
clean_yarn() { _clean_simple yarn $# yarn cache clean; }
clean_pnpm() { _clean_simple pnpm $# pnpm store prune; }
clean_composer() { _clean_simple composer $# composer clear-cache; }
clean_go() { _clean_simple go $# go clean -modcache; }

clean_npm() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage clean npm)"
  npm_cache_clear
}

clean_docker() {
  parse_yes_only "$(jack_usage clean docker)" "$@"
  if [ "$ASSUME_YES" -eq 1 ]; then
    docker_prune -y
  else
    docker_prune
  fi
}
