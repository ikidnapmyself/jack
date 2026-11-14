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

@test "flush-dns uses resolvectl when present" {
  stub_cmd id 'echo 0'
  stub_cmd resolvectl ''
  stub_cmd service ''
  run "$JACK" ubuntu flush-dns
  [ "$status" -eq 0 ]
  logged "resolvectl flush-caches"
  not_logged_like "^service"
}

@test "flush-dns restarts named and nscd with -y when resolvectl is absent" {
  isolate_path
  stub_cmd id 'echo 0'
  stub_cmd service ''
  run "$JACK" ubuntu flush-dns -y
  [ "$status" -eq 0 ]
  logged "service named restart"
  logged "service nscd restart"
}

@test "flush-dns asks before restarting services" {
  isolate_path
  stub_cmd id 'echo 0'
  stub_cmd service ''
  run "$JACK" ubuntu flush-dns <<< "n"
  [ "$status" -eq 1 ]
  not_logged_like "^service"
}

@test "flush-dns tolerates a missing named but fails when nothing restarts" {
  isolate_path
  stub_cmd id 'echo 0'
  stub_cmd service '[ "$1" = named ] && exit 1; exit 0'
  run "$JACK" ubuntu flush-dns -y
  [ "$status" -eq 0 ]
  stub_cmd service 'exit 1'
  run "$JACK" ubuntu flush-dns -y
  [ "$status" -eq 1 ]
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

make_sized_files() {
  BIG_DIR="$BATS_TEST_TMPDIR/big"
  mkdir -p "$BIG_DIR/sub"
  head -c 5000 /dev/zero > "$BIG_DIR/large"
  head -c 5000 /dev/zero > "$BIG_DIR/sub/large2"
  head -c 10 /dev/zero > "$BIG_DIR/small"
}

@test "big-files lists only files over the size" {
  make_sized_files
  run "$JACK" ubuntu big-files 1k "$BIG_DIR"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sort)" = "$(printf '%s\n%s' "$BIG_DIR/large" "$BIG_DIR/sub/large2")" ]
}

@test "big-files with no matches exits 1" {
  make_sized_files
  run "$JACK" ubuntu big-files 1M "$BIG_DIR"
  [ "$status" -eq 1 ]
}

@test "big-files rejects a bad size" {
  make_sized_files
  run "$JACK" ubuntu big-files '1k;x' "$BIG_DIR"
  [ "$status" -eq 2 ]
  run "$JACK" ubuntu big-files k "$BIG_DIR"
  [ "$status" -eq 2 ]
}

@test "big-files-delete -y deletes the matches and keeps the rest" {
  make_sized_files
  run "$JACK" ubuntu big-files-delete 1k "$BIG_DIR" -y
  [ "$status" -eq 0 ]
  [ ! -e "$BIG_DIR/large" ]
  [ ! -e "$BIG_DIR/sub/large2" ]
  [ -e "$BIG_DIR/small" ]
}

@test "big-files-delete lists the count and aborts when declined" {
  make_sized_files
  run "$JACK" ubuntu big-files-delete 1k "$BIG_DIR" <<< "n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 file(s)"* ]]
  [ -e "$BIG_DIR/large" ]
}

@test "big-files-delete with no matches exits 1 without prompting" {
  make_sized_files
  run "$JACK" ubuntu big-files-delete 1M "$BIG_DIR" < /dev/null
  [ "$status" -eq 1 ]
  [[ "$output" != *"[y/N]"* ]]
}

@test "big-files rejects sizes without a non-zero number and a unit" {
  make_sized_files
  for size in 0 100 0k 5c 5b 05k k; do
    run "$JACK" ubuntu big-files "$size" "$BIG_DIR"
    [ "$status" -eq 2 ]
  done
  [ -e "$BIG_DIR/large" ]
}

@test "big-files-delete rejects sizes without a non-zero number and a unit" {
  make_sized_files
  for size in 0 100 0k 5c 5b 05k k; do
    run "$JACK" ubuntu big-files-delete "$size" "$BIG_DIR" -y
    [ "$status" -eq 2 ]
  done
  [ -e "$BIG_DIR/large" ]
  [ -e "$BIG_DIR/sub/large2" ]
  [ -e "$BIG_DIR/small" ]
}

@test "big-files-delete deletes the listed files with spaces in names" {
  make_sized_files
  head -c 5000 /dev/zero > "$BIG_DIR/with space"
  run "$JACK" ubuntu big-files-delete 1k "$BIG_DIR" -y
  [ "$status" -eq 0 ]
  [ ! -e "$BIG_DIR/with space" ]
  [ -e "$BIG_DIR/small" ]
}

@test "count and big-files reject a directory starting with a dash" {
  run "$JACK" ubuntu count -x
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid directory"* ]]
  run "$JACK" ubuntu big-files 1k -x
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid directory"* ]]
}

@test "big-files-delete rejects a directory starting with a dash" {
  run "$JACK" ubuntu big-files-delete 1k -x
  [ "$status" -eq 2 ]
}

@test "mount needs root" {
  mkdir -p "$BATS_TEST_TMPDIR/mnt"
  stub_cmd id 'echo 501'
  stub_cmd mount ''
  run "$JACK" ubuntu mount /dev/sdb1 "$BATS_TEST_TMPDIR/mnt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo jack ubuntu mount /dev/sdb1"* ]]
  not_logged_like "^mount"
}

@test "mount mounts the device as root" {
  mkdir -p "$BATS_TEST_TMPDIR/mnt"
  stub_cmd id 'echo 0'
  stub_cmd mount ''
  run "$JACK" ubuntu mount /dev/sdb1 "$BATS_TEST_TMPDIR/mnt"
  [ "$status" -eq 0 ]
  logged "mount -o nosuid,nodev,noexec /dev/sdb1 $BATS_TEST_TMPDIR/mnt"
}

@test "mount rejects a device path with traversal" {
  mkdir -p "$BATS_TEST_TMPDIR/mnt"
  stub_cmd id 'echo 0'
  stub_cmd mount ''
  run "$JACK" ubuntu mount /dev/../tmp/x.img "$BATS_TEST_TMPDIR/mnt"
  [ "$status" -eq 2 ]
  not_logged_like "^mount"
}

@test "big-files-delete handles newlines in names and refuses /" {
  BIG_DIR="$BATS_TEST_TMPDIR/big"
  mkdir -p "$BIG_DIR"
  cd "$BATS_TEST_TMPDIR"
  : > keep.db
  head -c 3000 /dev/zero > "$BIG_DIR/junk
keep.db"
  run "$JACK" ubuntu big-files-delete 1k "$BIG_DIR" -y
  [ "$status" -eq 0 ]
  [ -f keep.db ]
  run "$JACK" ubuntu big-files-delete 1k / -y
  [ "$status" -eq 2 ]
}

@test "mount validates device and target before the root check" {
  stub_cmd id 'echo 501'
  stub_cmd mount ''
  run "$JACK" ubuntu mount sdb1 "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
  run "$JACK" ubuntu mount /dev/sdb1 "$BATS_TEST_TMPDIR/nope"
  [ "$status" -eq 2 ]
  run "$JACK" ubuntu mount /dev/sdb1
  [ "$status" -eq 2 ]
}
