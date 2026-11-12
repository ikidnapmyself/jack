#!/usr/bin/env bats

load test_helper

setup() {
  setup_stubs
  export JACK_PROC_DIR="$BATS_TEST_TMPDIR/proc"
  mkdir -p "$JACK_PROC_DIR/101" "$JACK_PROC_DIR/202" "$JACK_PROC_DIR/303"
  printf 'Name:\tbig\nVmSwap:\t  2048 kB\n' > "$JACK_PROC_DIR/101/status"
  printf 'Name:\tsmall\nVmSwap:\t  512 kB\n' > "$JACK_PROC_DIR/202/status"
  printf 'Name:\tnone\nVmSwap:\t  0 kB\n' > "$JACK_PROC_DIR/303/status"
  write_meminfo 16777216 8388608 4194304 1048576
}

write_meminfo() {
  printf 'MemTotal: %s kB\nMemFree: 1000 kB\nMemAvailable: %s kB\nSwapTotal: %s kB\nSwapFree: %s kB\n' \
    "$1" "$2" "$3" "$4" > "$JACK_PROC_DIR/meminfo"
}

@test "swap on Linux shows usage, verdict and top swap users" {
  JACK_UNAME=Linux run "$JACK" mem swap
  [ "$status" -eq 0 ]
  [[ "$output" == *"Swap"*"3.0G used of 4.0G (75%)"* ]]
  [[ "$output" == *"RAM"*"8.0G available of 16.0G (50%)"* ]]
  [[ "$output" == *"busy"* ]]
  [[ "$output" == *"101"*"big"* ]]
  [[ "$output" == *"202"*"small"* ]]
  [[ "$output" != *"none"* ]]
}

@test "swap verdict is ok with light swap and plenty of RAM" {
  write_meminfo 16777216 8388608 4194304 4194304
  JACK_UNAME=Linux run "$JACK" mem swap
  [[ "$output" == *"ok"* ]]
  [[ "$output" != *"PID"* ]]
}

@test "swap verdict is under pressure when RAM is nearly gone" {
  write_meminfo 16777216 524288 4194304 4194304
  JACK_UNAME=Linux run "$JACK" mem swap
  [[ "$output" == *"under pressure"* ]]
}

@test "swap handles a machine with no swap" {
  write_meminfo 16777216 8388608 0 0
  JACK_UNAME=Linux run "$JACK" mem swap
  [ "$status" -eq 0 ]
  [[ "$output" == *"none configured"* ]]
}

@test "swap on macOS reads sysctl and points to mem top" {
  stub_cmd sysctl 'case "$2" in
    hw.memsize) echo 17179869184 ;;
    kern.memorystatus_level) echo 40 ;;
    vm.swapusage) echo "total = 2048.00M  used = 1024.00M  free = 1024.00M  (encrypted)" ;;
  esac'
  JACK_UNAME=Darwin run "$JACK" mem swap
  [ "$status" -eq 0 ]
  [[ "$output" == *"1.0G used of 2.0G (50%)"* ]]
  [[ "$output" == *"6.4G available of 16.0G (40%)"* ]]
  [[ "$output" == *"jack mem top"* ]]
}

@test "usage shows total, used and available" {
  JACK_UNAME=Linux run "$JACK" mem usage
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total"*"16.0G"* ]]
  [[ "$output" == *"Used"*"8.0G (50%)"* ]]
  [[ "$output" == *"Available"*"8.0G (50%)"* ]]
}

@test "missing meminfo fails cleanly" {
  rm "$JACK_PROC_DIR/meminfo"
  JACK_UNAME=Linux run "$JACK" mem usage
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot read"* ]]
  [[ "$output" != *"integer expression"* ]]
}

@test "top ranks programs by memory and trims paths" {
  stub_cmd ps 'printf "%s\n" "  1024 11 /usr/bin/small" "  204800 22 /Applications/My App.app/Contents/MacOS/My App" "  2048 33 /bin/mid"'
  run "$JACK" mem top 2
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n 2p)" = "200M     22       My App" ]
  [[ "$output" == *"mid"* ]]
  [[ "$output" != *"small"* ]]
}

@test "top rejects a bad count" {
  run "$JACK" mem top abc
  [ "$status" -eq 2 ]
  run "$JACK" mem top 51
  [ "$status" -eq 2 ]
}

@test "swap rejects extra arguments" {
  run "$JACK" mem swap now
  [ "$status" -eq 2 ]
}
