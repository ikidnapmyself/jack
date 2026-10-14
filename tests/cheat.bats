#!/usr/bin/env bats

load test_helper

@test "list shows every theme with its actions and docs" {
  run "$JACK" cheat list
  [ "$status" -eq 0 ]
  [[ "$output" == *"port"* ]]
  [[ "$output" == *"Kill whatever listens on a port"* ]]
}

@test "list never shows core" {
  run "$JACK" cheat list
  [[ "$output" != *"core"* ]]
}

@test "list with a theme shows only that theme" {
  run "$JACK" cheat list port
  [ "$status" -eq 0 ]
  [[ "$output" == *"kill"* ]]
  [[ "$output" != *"cheat"* ]]
}

@test "list with an unknown theme exits 2" {
  run "$JACK" cheat list nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown theme"* ]]
}
