JACK_DESC="Git chores"
JACK_DOC_reset_remote="Hard reset the branch to its upstream after saving a backup branch"
JACK_ALIAS_reset_remote="greset"
JACK_DOC_remote_url="Show the origin remote"
JACK_ALIAS_remote_url="gurl"
JACK_DOC_submodules="Init and update submodules recursively"
JACK_ALIAS_submodules="gsub"
JACK_USAGE_reset_remote="[-y]"
JACK_USAGE_remote_url=""
JACK_USAGE_submodules=""

git_reset_remote() {
  parse_yes_only "$(jack_usage git reset-remote)" "$@"
  require_cmd git
  local branch upstream remote backup
  branch="$(git symbolic-ref --short -q HEAD)" || die "detached HEAD, nothing to reset"
  upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || die "$branch has no upstream"
  remote="$(git config "branch.$branch.remote")"
  [ -n "$remote" ] || die "$branch has no upstream remote"
  if [ "$remote" != . ]; then
    git fetch "$remote" || die "fetch failed"
  fi
  backup="backup/$branch-$(date +%Y%m%d-%H%M%S)"
  if [ -n "$(git status --porcelain)" ]; then
    echo "${YELLOW}working tree is dirty, uncommitted changes will be lost${RESET}"
  fi
  confirm_unless_yes "Reset $branch to $upstream? Backup: $backup" "$ASSUME_YES" || return 1
  git branch "$backup" || die "could not create $backup"
  git reset --hard "$upstream"
}

git_remote_url() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage git remote-url)"
  require_cmd git
  git remote show origin
}

git_submodules() {
  [ $# -eq 0 ] || die_usage "usage: $(jack_usage git submodules)"
  require_cmd git
  git submodule update --init --recursive
}
