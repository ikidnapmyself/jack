JACK="$BATS_TEST_DIRNAME/../bin/jack"
export JACK_CONFIG_DIR="${BATS_TMPDIR:-/tmp}/jack-test-config"

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

wait_for_port() {
  local i
  for i in $(seq 1 100); do
    lsof -nP -iTCP:"$1" -sTCP:LISTEN -t >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

# A listener left holding fd 3 makes bats wait for it forever, so close it.
_spawn_listener() {
  local pidfile="$BATS_TEST_TMPDIR/listener.pid"
  ( python3 -c '
import signal, socket, sys, time
if sys.argv[2] == "stubborn":
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(sys.argv[1])))
s.listen()
time.sleep(120)
' "$1" "$2" jack-test-listener >/dev/null 2>&1 3>&- &
    echo $! > "$pidfile" )
  LISTENER_PID="$(cat "$pidfile")"
  wait_for_port "$1"
}

start_listener() {
  _spawn_listener "$1" plain
}

start_stubborn_listener() {
  _spawn_listener "$1" stubborn
}

stop_listener() {
  [ -n "${LISTENER_PID:-}" ] && kill -9 "$LISTENER_PID" 2>/dev/null
  return 0
}

port_is_free() {
  [ -z "$(lsof -nP -iTCP:"$1" -sTCP:LISTEN -t 2>/dev/null)" ]
}

setup_stubs() {
  STUB_DIR="$BATS_TEST_TMPDIR/stubs"
  STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  mkdir -p "$STUB_DIR"
  : > "$STUB_LOG"
  PATH="$STUB_DIR:$PATH"
  export STUB_LOG
}

stub_cmd() {
  local name="$1" body="${2:-}"
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$STUB_LOG"\n%s\n' "$name" "$body" > "$STUB_DIR/$name"
  chmod +x "$STUB_DIR/$name"
}

isolate_path() {
  local bin="$BATS_TEST_TMPDIR/bin" tool src
  mkdir -p "$bin"
  for tool in bash env sed tr head wc awk id find rm mkdir chmod touch basename dirname cat uname readlink grep sort; do
    src="$(command -v "$tool")"
    case "$src" in
      /*) ln -sf "$src" "$bin/$tool" ;;
    esac
  done
  PATH="$STUB_DIR:$bin"
}

logged() {
  grep -qxF -- "$1" "$STUB_LOG"
}

not_logged_like() {
  ! grep -q -- "$1" "$STUB_LOG"
}
