#!/usr/bin/env bats

load test_helper

setup() {
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git init -q --bare -b main "$BATS_TEST_TMPDIR/remote.git"
  git init -q -b main "$BATS_TEST_TMPDIR/a"
  cd "$BATS_TEST_TMPDIR/a"
  git remote add origin "$BATS_TEST_TMPDIR/remote.git"
  echo one > f
  git add f
  git commit -q -m one
  git push -q -u origin main
  git clone -q "$BATS_TEST_TMPDIR/remote.git" "$BATS_TEST_TMPDIR/b"
  git -C "$BATS_TEST_TMPDIR/b" commit -q --allow-empty -m two
  git -C "$BATS_TEST_TMPDIR/b" push -q origin main
  echo local > g
  git add g
  git commit -q -m local
}

@test "reset-remote -y moves to upstream and keeps a backup branch" {
  old="$(git rev-parse HEAD)"
  run "$JACK" git reset-remote -y
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]
  [ "$(git for-each-ref --format='%(objectname)' refs/heads/backup)" = "$old" ]
}

@test "reset-remote aborts when declined" {
  old="$(git rev-parse HEAD)"
  run "$JACK" git reset-remote <<< "n"
  [ "$status" -eq 1 ]
  [ "$(git rev-parse HEAD)" = "$old" ]
  [ -z "$(git for-each-ref refs/heads/backup)" ]
}

@test "reset-remote warns about a dirty tree" {
  echo changed >> f
  run "$JACK" git reset-remote -y
  [ "$status" -eq 0 ]
  [[ "$output" == *"dirty"* ]]
}

@test "reset-remote without an upstream exits 1" {
  git switch -q -c lone
  run "$JACK" git reset-remote -y
  [ "$status" -eq 1 ]
  [[ "$output" == *"no upstream"* ]]
}

@test "remote-url shows the origin remote" {
  run "$JACK" git remote-url
  [ "$status" -eq 0 ]
  [[ "$output" == *"remote.git"* ]]
}

@test "submodules updates recursively" {
  setup_stubs
  stub_cmd git ''
  run "$JACK" git submodules
  [ "$status" -eq 0 ]
  logged "git submodule update --init --recursive"
}
