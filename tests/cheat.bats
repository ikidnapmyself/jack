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

@test "list marks themes for another OS as Disabled" {
  JACK_UNAME=Linux run "$JACK" cheat list
  [[ "$output" == *"mac (Disabled)"* ]]
  [[ "$output" != *"ubuntu (Disabled)"* ]]
}

@test "explain with no arguments describes every theme and its safety" {
  run "$JACK" cheat explain
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean: Cache and disk cleanup"* ]]
  [[ "$output" == *"Nothing you wrote is touched"* ]]
}

@test "explain with a theme covers every action in it" {
  run "$JACK" cheat explain port
  [ "$status" -eq 0 ]
  [[ "$output" == *"jack port list [port]"* ]]
  [[ "$output" == *"jack port kill <port> [-y]"* ]]
  [[ "$output" == *"Unsaved work"* ]]
}

@test "explain with a theme and action shows usage, doc and details" {
  run "$JACK" cheat explain clean pip
  [ "$status" -eq 0 ]
  [[ "$output" == *"jack clean pip"* ]]
  [[ "$output" == *"Purge the pip cache"* ]]
  [[ "$output" == *"downloads them again"* ]]
}

@test "explain accepts hyphenated action names" {
  run "$JACK" cheat explain ubuntu big-files-delete
  [ "$status" -eq 0 ]
  [[ "$output" == *"no trash"* ]]
}

@test "explain rejects unknown themes and actions" {
  run "$JACK" cheat explain nope
  [ "$status" -eq 2 ]
  run "$JACK" cheat explain port nope
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown action"* ]]
}

