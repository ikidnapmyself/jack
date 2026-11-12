#!/usr/bin/env bats

load test_helper

setup() {
  setup_stubs
  export CRONTAB_FILE="$BATS_TEST_TMPDIR/crontab"
  export JACK_CRON_NOW="2026-11-09 14:30"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  stub_cmd crontab 'cat "$CRONTAB_FILE"'
}

crontab_with() {
  printf '%s\n' "$@" > "$CRONTAB_FILE"
}

@test "list shows the next run for a simple schedule" {
  crontab_with "45 14 * * * echo hi"
  run "$JACK" cron list
  [ "$status" -eq 0 ]
  [[ "$output" == *"SCHEDULE"* ]]
  [[ "$output" == *"Mon 2026-11-09 14:45"* ]]
  [[ "$output" == *"echo hi"* ]]
}

@test "list skips comments, blanks and env lines" {
  crontab_with "# note" "" "MAILTO=me@example.com" "0 0 * * * a" "0 1 * * * b"
  run "$JACK" cron list
  [ "$status" -eq 0 ]
  [[ "$output" == *"1   0_0_*_*_*"* ]]
  [[ "$output" == *"2   0_1_*_*_*"* ]]
  [[ "$output" != *"MAILTO"* ]]
}

@test "list never returns the current minute" {
  crontab_with "30 14 * * * now"
  run "$JACK" cron list
  [[ "$output" == *"Tue 2026-11-10 14:30"* ]]
}

@test "list count shows several runs" {
  crontab_with "*/15 * * * * tick"
  run "$JACK" cron list 3
  [[ "$output" == *"Mon 2026-11-09 14:45"* ]]
  [[ "$output" == *"Mon 2026-11-09 15:00"* ]]
  [[ "$output" == *"Mon 2026-11-09 15:15"* ]]
}

@test "list handles macros" {
  crontab_with "@daily d" "@hourly h" "@weekly w" "@monthly m" "@reboot r"
  run "$JACK" cron list
  [[ "$output" == *"Tue 2026-11-10 00:00"* ]]
  [[ "$output" == *"Mon 2026-11-09 15:00"* ]]
  [[ "$output" == *"Sun 2026-11-15 00:00"* ]]
  [[ "$output" == *"Tue 2026-12-01 00:00"* ]]
  [[ "$output" == *"at boot"* ]]
}

@test "list handles ranges, lists and weekday names" {
  crontab_with "0 9-10 * * mon-fri x" "0 8 1,15 * * y"
  run "$JACK" cron list 2
  [[ "$output" == *"Tue 2026-11-10 09:00"* ]]
  [[ "$output" == *"Tue 2026-11-10 10:00"* ]]
  [[ "$output" == *"Sun 2026-11-15 08:00"* ]]
  [[ "$output" == *"Tue 2026-12-01 08:00"* ]]
}

@test "dom and weekday both set match either" {
  crontab_with "0 0 13 * fri z"
  run "$JACK" cron list 2
  [[ "$output" == *"Fri 2026-11-13 00:00"* ]]
  [[ "$output" == *"Fri 2026-11-20 00:00"* ]]
}

@test "list rolls over the year and leap days" {
  export JACK_CRON_NOW="2027-12-31 23:59"
  crontab_with "0 0 29 2 * leap"
  run "$JACK" cron list
  [[ "$output" == *"Tue 2028-02-29 00:00"* ]]
}

@test "list reports impossible and invalid schedules without failing" {
  crontab_with "0 0 31 2 * never" "61 * * * * bad" "0 0 * * * ok"
  run "$JACK" cron list
  [ "$status" -eq 0 ]
  [[ "$output" == *"never"* ]]
  [[ "$output" == *"invalid schedule"* ]]
  [[ "$output" == *"Tue 2026-11-10 00:00"* ]]
}

@test "list with no jobs exits 1" {
  : > "$CRONTAB_FILE"
  run "$JACK" cron list
  [ "$status" -eq 1 ]
  [[ "$output" == *"no cron jobs"* ]]
}

@test "list rejects a bad count" {
  crontab_with "0 0 * * * a"
  run "$JACK" cron list abc
  [ "$status" -eq 2 ]
}

@test "logs without a number lists only jobs whose log file exists" {
  printf 'x\n' > "$BATS_TEST_TMPDIR/a.log"
  printf 'y\n' > "$HOME/c.log"
  crontab_with "0 0 * * * a >> $BATS_TEST_TMPDIR/a.log 2>&1" "0 0 * * * b >> /dev/null 2>&1" "0 0 * * * c >> ~/c.log" "0 0 * * * d >> /nope/d.log"
  run "$JACK" cron logs
  [ "$status" -eq 0 ]
  [[ "$output" == *"$BATS_TEST_TMPDIR/a.log"* ]]
  [[ "$output" == *"$HOME/c.log"* ]]
  [[ "$output" != *"/dev/null"*"/nope"* ]]
  [[ "$output" != *"d.log"*" d "* ]]
  [[ "$output" != *"$HOME/>"* ]]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 3 ]
}

@test "logs without a number and no log files exits 1" {
  crontab_with "0 0 * * * a >> /dev/null 2>&1"
  run "$JACK" cron logs
  [ "$status" -eq 1 ]
  [[ "$output" == *"no job has a log file"* ]]
}

@test "logs tails the job log file" {
  printf 'one\ntwo\nthree\n' > "$BATS_TEST_TMPDIR/job.log"
  crontab_with "0 0 * * * cd /x && run >> $BATS_TEST_TMPDIR/job.log 2>&1 # note"
  run "$JACK" cron logs 1 2
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'two\nthree')" ]
}

@test "logs falls back to the system log when the job has no file" {
  stub_cmd journalctl 'echo "Nov 9 CRON[1]: (u) CMD (backup --now)"; echo "Nov 9 CRON[2]: (u) CMD (other)"'
  crontab_with "0 0 * * * backup --now"
  JACK_UNAME=Linux run "$JACK" cron logs 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"backup --now"* ]]
  [[ "$output" != *"other"* ]]
}

@test "logs on macOS reads the unified log" {
  stub_cmd log 'echo "2026 cron: (u) CMD (backup --now)"'
  crontab_with "0 0 * * * backup --now"
  JACK_UNAME=Darwin run "$JACK" cron logs 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"backup --now"* ]]
}

@test "logs rejects an unknown job" {
  crontab_with "0 0 * * * a"
  run "$JACK" cron logs 5
  [ "$status" -eq 1 ]
  [[ "$output" == *"no cron job 5"* ]]
}
