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
