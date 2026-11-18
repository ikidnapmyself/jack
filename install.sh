#!/bin/sh
# Install or update jack. Run with: curl -fsSL https://raw.githubusercontent.com/ikidnapmyself/jack/main/install.sh | sh
# Uninstall with: curl -fsSL https://raw.githubusercontent.com/ikidnapmyself/jack/main/install.sh | sh -s -- --uninstall
set -eu

JACK_REPO="${JACK_REPO:-https://github.com/ikidnapmyself/jack.git}"
JACK_REF="${JACK_REF:-main}"
JACK_DIR="${JACK_DIR:-$HOME/.local/share/jack}"
JACK_BIN_DIR="${JACK_BIN_DIR:-$HOME/.local/bin}"

say() { printf 'jack: %s\n' "$*"; }
die() { printf 'jack: %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "$1 is required but not installed"
}

link_points_into_dir() {
  [ -L "$1" ] || return 1
  case "$(readlink "$1")" in
    "$JACK_DIR"/*) return 0 ;;
  esac
  return 1
}

uninstall() {
  link="$JACK_BIN_DIR/jack"
  if link_points_into_dir "$link"; then
    rm "$link"
    say "removed $link"
  fi
  if [ -d "$JACK_DIR/.git" ]; then
    rm -rf "$JACK_DIR"
    say "removed $JACK_DIR"
  fi
  say "config in ${XDG_CONFIG_HOME:-$HOME/.config}/jack was left in place"
}

install() {
  need git
  need bash

  link="$JACK_BIN_DIR/jack"
  if [ -e "$link" ] || [ -L "$link" ]; then
    link_points_into_dir "$link" || die "$link exists and isn't a jack link, remove it or set JACK_BIN_DIR"
  fi

  if [ -d "$JACK_DIR/.git" ]; then
    say "updating $JACK_DIR"
    git -C "$JACK_DIR" fetch --quiet origin "$JACK_REF"
    git -C "$JACK_DIR" checkout --quiet "$JACK_REF"
    git -C "$JACK_DIR" merge --quiet --ff-only FETCH_HEAD
  elif [ -e "$JACK_DIR" ]; then
    die "$JACK_DIR exists and isn't a jack checkout, set JACK_DIR to another path"
  else
    say "cloning into $JACK_DIR"
    mkdir -p "$(dirname "$JACK_DIR")"
    git clone --quiet --branch "$JACK_REF" "$JACK_REPO" "$JACK_DIR"
  fi

  mkdir -p "$JACK_BIN_DIR"
  rm -f "$link"
  ln -s "$JACK_DIR/bin/jack" "$link"
  say "linked $link"

  say "installed $("$link" --version)"

  case ":$PATH:" in
    *":$JACK_BIN_DIR:"*) ;;
    *)
      say "$JACK_BIN_DIR isn't on your PATH, add this to your shell rc:"
      printf "\n  export PATH=\"%s:\$PATH\"\n\n" "$JACK_BIN_DIR"
      ;;
  esac

  shell_name="$(basename "${SHELL:-sh}")"
  case "$shell_name" in
    zsh|bash)
      say "for tab completion, add this to ~/.${shell_name}rc:"
      printf "\n  command -v jack >/dev/null && eval \"\$(jack completion %s)\"\n\n" "$shell_name"
      ;;
  esac
}

case "${1:-}" in
  --uninstall) uninstall ;;
  "") install ;;
  *) die "unknown option: $1" ;;
esac
