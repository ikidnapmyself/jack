#!/usr/bin/env bats

load test_helper

setup() {
  setup_stubs
  cd "$BATS_TEST_TMPDIR"
  export USER=alice
  stub_cmd mysqldump 'echo "-- dump"'
}

@test "dump writes the dump to the file" {
  run "$JACK" mysql dump mydb out.sql
  [ "$status" -eq 0 ]
  logged "mysqldump -u alice -p mydb"
  [ "$(cat out.sql)" = "-- dump" ]
}

@test "dump passes tables and an explicit user" {
  run "$JACK" mysql dump -u bob mydb out.sql users orders
  [ "$status" -eq 0 ]
  logged "mysqldump -u bob -p mydb users orders"
}

@test "dump accepts -u after the positional args" {
  run "$JACK" mysql dump mydb out.sql users -u bob
  [ "$status" -eq 0 ]
  logged "mysqldump -u bob -p mydb users"
}

@test "dump without enough args exits 2" {
  run "$JACK" mysql dump mydb
  [ "$status" -eq 2 ]
}

@test "dump rejects unknown options" {
  run "$JACK" mysql dump --evil mydb out.sql
  [ "$status" -eq 2 ]
}

@test "dump rejects a bad database name" {
  run "$JACK" mysql dump 'a;b' out.sql
  [ "$status" -eq 2 ]
  not_logged_like "^mysqldump"
}

@test "dump refuses to overwrite an existing file" {
  echo keep > out.sql
  run "$JACK" mysql dump mydb out.sql
  [ "$status" -eq 1 ]
  [[ "$output" == *"exists"* ]]
  [ "$(cat out.sql)" = "keep" ]
}

@test "dump removes the partial file when mysqldump fails" {
  stub_cmd mysqldump 'exit 1'
  run "$JACK" mysql dump mydb out.sql
  [ "$status" -eq 1 ]
  [ ! -e out.sql ]
}
