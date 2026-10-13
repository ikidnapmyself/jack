#!/usr/bin/env bats

load test_helper

setup() {
  PORT="$(free_port)"
}

teardown() {
  stop_listener
}

@test "list shows a listener with port, pid and command line" {
  start_listener "$PORT"
  run "$JACK" port list
  [ "$status" -eq 0 ]
  [[ "$output" == *"PORT"* ]]
  [[ "$output" == *"$PORT"* ]]
  [[ "$output" == *"$LISTENER_PID"* ]]
  [[ "$output" == *"http.server"* ]]
}

@test "list with a port filters to that port" {
  start_listener "$PORT"
  run "$JACK" port list "$PORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$LISTENER_PID"* ]]
}

@test "list with an unused port exits 1" {
  run "$JACK" port list "$PORT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no TCP listeners"* ]]
}

@test "list rejects non-numeric port" {
  run "$JACK" port list abc
  [ "$status" -eq 2 ]
}

@test "list rejects out of range ports" {
  run "$JACK" port list 0
  [ "$status" -eq 2 ]
  run "$JACK" port list 70000
  [ "$status" -eq 2 ]
}

@test "list rejects overlong and zero-padded ports" {
  run "$JACK" port list 99999999999999999999
  [ "$status" -eq 2 ]
  [[ "$output" != *"integer expression"* ]]
  run "$JACK" port list 007
  [ "$status" -eq 2 ]
}

@test "kill without a port exits 2" {
  run "$JACK" port kill
  [ "$status" -eq 2 ]
}

@test "kill rejects invalid port and unknown flag" {
  run "$JACK" port kill abc
  [ "$status" -eq 2 ]
  run "$JACK" port kill -z "$PORT"
  [ "$status" -eq 2 ]
}

@test "kill on an unused port exits 1" {
  run "$JACK" port kill -y "$PORT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing listening"* ]]
}

@test "kill -y terminates the listener" {
  start_listener "$PORT"
  run "$JACK" port kill -y "$PORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$LISTENER_PID"* ]]
  port_is_free "$PORT"
}

@test "kill aborts when the answer is n" {
  start_listener "$PORT"
  run bash -c "echo n | '$JACK' port kill '$PORT'"
  [ "$status" -eq 1 ]
  ! port_is_free "$PORT"
}

@test "kill proceeds when the answer is y" {
  start_listener "$PORT"
  run bash -c "echo y | '$JACK' port kill '$PORT'"
  [ "$status" -eq 0 ]
  port_is_free "$PORT"
}

@test "kill escalates to SIGKILL when SIGTERM is ignored" {
  start_stubborn_listener "$PORT"
  run "$JACK" port kill -y "$PORT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SIGKILL"* ]]
  port_is_free "$PORT"
}

@test "kill re-resolves PIDs after the confirm and skips a listener that died" {
  start_listener "$PORT"
  ( sleep 0.3; kill -9 "$LISTENER_PID" ) &
  run bash -c "(sleep 1.5; echo y) | '$JACK' port kill '$PORT'"
  wait
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing listening"* ]]
  [[ "$output" != *"already gone"* ]]
  [[ "$output" != *"terminated"* ]]
}
