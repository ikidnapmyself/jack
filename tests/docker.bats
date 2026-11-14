#!/usr/bin/env bats

load test_helper

setup() {
  setup_stubs
}

@test "stop -y stops running containers" {
  stub_cmd docker 'case "$1" in ps) printf "abc\ndef\n" ;; esac'
  run "$JACK" docker stop -y
  [ "$status" -eq 0 ]
  logged "docker ps -q"
  logged "docker stop abc def"
}

@test "stop proceeds when the prompt is accepted" {
  stub_cmd docker 'case "$1" in ps) echo abc ;; esac'
  run "$JACK" docker stop <<< "y"
  [ "$status" -eq 0 ]
  logged "docker stop abc"
}

@test "stop aborts when the prompt is declined" {
  stub_cmd docker 'case "$1" in ps) echo abc ;; esac'
  run "$JACK" docker stop <<< "n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"aborted"* ]]
  not_logged_like "^docker stop"
}

@test "stop with nothing running says so" {
  stub_cmd docker ''
  run "$JACK" docker stop -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to stop"* ]]
  not_logged_like "^docker stop"
}

@test "stop rejects unknown options" {
  stub_cmd docker ''
  run "$JACK" docker stop --force
  [ "$status" -eq 2 ]
}

@test "rm -y removes exited containers" {
  stub_cmd docker 'case "$1" in ps) printf "abc\ndef\n" ;; esac'
  run "$JACK" docker rm -y
  [ "$status" -eq 0 ]
  logged "docker ps -aq -f status=exited"
  logged "docker rm abc def"
}

@test "rm aborts when declined" {
  stub_cmd docker 'case "$1" in ps) echo abc ;; esac'
  run "$JACK" docker rm <<< "n"
  [ "$status" -eq 1 ]
  not_logged_like "^docker rm"
}

@test "rm with nothing stopped says so" {
  stub_cmd docker ''
  run "$JACK" docker rm -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to remove"* ]]
}

@test "prune -y runs a forced system prune" {
  stub_cmd docker ''
  run "$JACK" docker prune -y
  [ "$status" -eq 0 ]
  logged "docker system prune -f"
}

@test "prune --volumes passes the flag through" {
  stub_cmd docker ''
  run "$JACK" docker prune --volumes -y
  [ "$status" -eq 0 ]
  logged "docker system prune -f --volumes"
}

@test "prune aborts when declined" {
  stub_cmd docker ''
  run "$JACK" docker prune <<< "n"
  [ "$status" -eq 1 ]
  not_logged_like "^docker system"
}

@test "ps uses the docker compose plugin when present" {
  stub_cmd docker ''
  run "$JACK" docker ps
  [ "$status" -eq 0 ]
  logged "docker compose ps"
}

@test "ps falls back to docker-compose" {
  stub_cmd docker 'case "$1" in compose) exit 1 ;; esac'
  stub_cmd docker-compose ''
  run "$JACK" docker ps
  [ "$status" -eq 0 ]
  logged "docker-compose ps"
}

@test "ps fails when neither compose flavour exists" {
  isolate_path
  run "$JACK" docker ps
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing command: docker compose"* ]]
}

@test "restart passes the service to the compose plugin" {
  stub_cmd docker ''
  run "$JACK" docker restart elasticsearch
  [ "$status" -eq 0 ]
  logged "docker compose restart elasticsearch"
}

@test "restart falls back to docker-compose" {
  stub_cmd docker 'case "$1" in compose) exit 1 ;; esac'
  stub_cmd docker-compose ''
  run "$JACK" docker restart elasticsearch
  [ "$status" -eq 0 ]
  logged "docker-compose restart elasticsearch"
}

@test "restart without a service exits 2" {
  stub_cmd docker ''
  run "$JACK" docker restart
  [ "$status" -eq 2 ]
}

@test "restart rejects a bad service name" {
  stub_cmd docker ''
  run "$JACK" docker restart 'a;b'
  [ "$status" -eq 2 ]
  not_logged_like "compose restart"
}

@test "stop surfaces a docker ps failure" {
  stub_cmd docker 'case "$1" in ps) exit 1 ;; esac'
  run "$JACK" docker stop -y
  [ "$status" -eq 1 ]
  [[ "$output" == *"docker ps failed"* ]]
  not_logged_like "^docker stop"
}

@test "rm surfaces a docker ps failure" {
  stub_cmd docker 'case "$1" in ps) exit 1 ;; esac'
  run "$JACK" docker rm -y
  [ "$status" -eq 1 ]
  [[ "$output" == *"docker ps failed"* ]]
  not_logged_like "^docker rm"
}

@test "stop, rm and prune skip with a notice when the daemon is off" {
  local act
  stub_cmd docker 'case "$1" in info) echo "Cannot connect to the Docker daemon at unix:///x. Is the docker daemon running?" >&2; exit 1 ;; esac'
  for act in stop rm prune; do
    run "$JACK" docker "$act" -y
    [ "$status" -eq 0 ] || { echo "$act status $status"; return 1; }
    [[ "$output" == *"docker isn't running, skipping"* ]] || { echo "$act: $output"; return 1; }
  done
  not_logged_like "^docker \(ps\|stop\|rm\|system\)"
}

@test "stop, rm and prune fail loudly on a non-daemon docker info error" {
  local act
  stub_cmd docker 'case "$1" in info) echo "permission denied while trying to connect" >&2; exit 1 ;; esac'
  for act in stop rm prune; do
    run "$JACK" docker "$act" -y
    [ "$status" -eq 1 ] || { echo "$act status $status"; return 1; }
    [[ "$output" == *"permission denied"* ]] || { echo "$act: $output"; return 1; }
  done
  not_logged_like "^docker \(ps\|stop\|rm\|system\)"
}
