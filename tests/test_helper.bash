JACK="$BATS_TEST_DIRNAME/../bin/jack"

free_port() {
  python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()'
}

wait_for_port() {
  local i
  for i in $(seq 1 50); do
    lsof -nP -iTCP:"$1" -sTCP:LISTEN -t >/dev/null 2>&1 && return 0
    sleep 0.1
  done
  return 1
}

capture_listener_pid() {
  LISTENER_PID="$(lsof -nP -iTCP:"$1" -sTCP:LISTEN -t | head -n 1)"
}

start_listener() {
  ( python3 -m http.server "$1" --bind 127.0.0.1 >/dev/null 2>&1 & )
  wait_for_port "$1"
  capture_listener_pid "$1"
}

start_stubborn_listener() {
  ( python3 -c '
import signal, socket, sys, time
signal.signal(signal.SIGTERM, signal.SIG_IGN)
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", int(sys.argv[1])))
s.listen()
time.sleep(60)
' "$1" >/dev/null 2>&1 & )
  wait_for_port "$1"
  capture_listener_pid "$1"
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

logged() {
  grep -qxF -- "$1" "$STUB_LOG"
}

not_logged_like() {
  ! grep -q -- "$1" "$STUB_LOG"
}
