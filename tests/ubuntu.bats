#!/usr/bin/env bats

load test_helper

setup() {
  setup_stubs
}

@test "flush-dns needs root" {
  stub_cmd id 'echo 501'
  stub_cmd service ''
  run "$JACK" ubuntu flush-dns
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo jack ubuntu flush-dns"* ]]
  not_logged_like "^service"
}

@test "flush-dns restarts named and nscd as root" {
  stub_cmd id 'echo 0'
  stub_cmd service ''
  run "$JACK" ubuntu flush-dns
  [ "$status" -eq 0 ]
  logged "service named restart"
  logged "service nscd restart"
}

@test "ports lists listening tcp sockets" {
  stub_cmd ss 'echo LISTEN'
  run "$JACK" ubuntu ports
  [ "$status" -eq 0 ]
  logged "ss -lntp"
}

@test "port-test reports an open port" {
  stub_cmd nc ''
  run "$JACK" ubuntu port-test example.com 80
  [ "$status" -eq 0 ]
  [[ "$output" == *"example.com:80 open"* ]]
  logged "nc -z -w 3 example.com 80"
}

@test "port-test reports a closed port with exit 1" {
  stub_cmd nc 'exit 1'
  run "$JACK" ubuntu port-test example.com 80
  [ "$status" -eq 1 ]
  [[ "$output" == *"example.com:80 closed"* ]]
}

@test "port-test validates its arguments" {
  stub_cmd nc ''
  run "$JACK" ubuntu port-test example.com 99999
  [ "$status" -eq 2 ]
  run "$JACK" ubuntu port-test -x 80
  [ "$status" -eq 2 ]
  run "$JACK" ubuntu port-test example.com
  [ "$status" -eq 2 ]
  not_logged_like "^nc"
}

@test "count counts files recursively" {
  mkdir -p "$BATS_TEST_TMPDIR/d/sub"
  touch "$BATS_TEST_TMPDIR/d/a" "$BATS_TEST_TMPDIR/d/b" "$BATS_TEST_TMPDIR/d/sub/c"
  run "$JACK" ubuntu count "$BATS_TEST_TMPDIR/d"
  [ "$status" -eq 0 ]
  [ "$output" = "3" ]
}

@test "count rejects a missing directory" {
  run "$JACK" ubuntu count "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
}

@test "mysql-config shows the default options lines" {
  stub_cmd mysql "printf 'noise\nDefault options are read from the following files\n/etc/my.cnf /etc/mysql/my.cnf\n'"
  run "$JACK" ubuntu mysql-config
  [ "$status" -eq 0 ]
  [[ "$output" == *"/etc/my.cnf"* ]]
  logged "mysql --verbose --help"
}

@test "ssh-key uses the shared helper" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  stub_cmd ssh-keygen ''
  run "$JACK" ubuntu ssh-key me@example.com
  [ "$status" -eq 0 ]
  logged "ssh-keygen -t ed25519 -C me@example.com -f $HOME/.ssh/id_ed25519"
}
