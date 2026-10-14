# jack: gist themes, cheat and alias

## Goal

Turn the terminal cheatsheet gist (Docker, Git, MacOS, MySQL, NPM, Ubuntu) into runnable jack themes. Add `cheat` to browse actions and `alias` to emit shell aliases. Jack is the single source of truth, so the cheatsheet cannot drift from the code.

## Decisions

- Python is out of scope. `venv activate` cannot run in a subshell.
- Theme names stay `[a-z]` only. OS themes are `mac` and `ubuntu`. No dispatcher change.
- Jack never runs sudo itself. Root actions exit with `run: sudo jack <theme> <action>` when not root.
- Modernized commands: `ss -lntp` instead of `netstat -lntp`, `nc -z` instead of `telnet`, ed25519 instead of RSA 4096 for `ssh-key`.
- Dropped as dead or too thin: Homebrew reinstall script, `brew update`, `brew doctor`, `git diff`, MySQL upgrade and restart, `python3` install.

## Metadata

Each theme file declares, per action:

- `JACK_DOC_<action>="one line description"`, required
- `JACK_ALIAS_<action>="name"`, optional

A helper in `lib/core.sh` reads these with `sed`. Theme files are never sourced for listing, so listing has no side effects. Bash 3.2 compatible, no associative arrays.

`jack <theme>` prints each action with its doc. Docs hold a description only, not the raw command. The function body is the command.

## cheat and alias

Both are ordinary themes, so the dispatcher needs no change.

- `jack cheat list [theme]` prints every action with its doc, grouped by theme.
- `jack alias print` emits `alias <name>='jack <theme> <action>'` for every `JACK_ALIAS_` line. Use with `eval "$(jack alias print)"` in `.zshrc`.

## Themes

Destructive actions prompt via `confirm` and accept `-y`.

### docker

- `stop`: stop all containers. Prints "nothing to stop" on an empty list.
- `rm`: remove stopped containers. Same empty-list handling.
- `prune [--volumes]`: `docker system prune`, with `--volumes` passed through.
- `ps`: `docker-compose ps`.
- `restart <service>`: `docker-compose restart <service>`.

### git

- `reset-remote`: fetch origin, then `reset --hard` to the current branch's upstream. First creates `backup/<branch>-<timestamp>` at HEAD. The prompt warns when the tree is dirty, since uncommitted changes are lost.
- `remote-url`: `git remote show origin`.
- `submodules`: `git submodule update --init --recursive`.

### npm

- `cache-clear`: `npm cache clear --force`.
- `global-setup`: create `~/.npm-global`, set the npm prefix, append the PATH export to `~/.profile` once. Idempotent. Prompts before editing the profile.

### mysql

- `dump <db> <file> [table...] [-u user]`: `mysqldump -u <user> -p <db> [tables] > <file>`.

### mac

- `flush-dns`: `killall -HUP mDNSResponder`. Needs root.
- `nginx-reload`: `nginx -s reload`. Needs root.
- `ssh-key <email>`: shared helper in `core.sh`.

### ubuntu

- `flush-dns`: restart `named` and `nscd`. Needs root.
- `ports`: `ss -lntp`.
- `port-test <host> <port>`: `nc -z`.
- `big-files <size> [dir]`: `find <dir> -type f -size +<size>`.
- `big-files-delete <size> [dir]`: lists matches and a count, prompts, then deletes.
- `count [dir]`: number of files under a directory.
- `mount <device> <target>`: needs root.
- `mysql-config`: list MySQL default option files.
- `ssh-key <email>`: shared helper in `core.sh`.

## Errors

Same contract as `port`.

- Usage errors exit 2 through `die_usage`.
- Missing tools exit 1 through `require_cmd`.
- A declined confirm exits 1 with "aborted".
- Nothing found exits 1 with a message on stderr.
- Every action validates arguments before touching anything.

## Testing

Bats, one file per theme. External commands are stubbed with fake executables first on `PATH`, defined in `tests/test_helper.bash`. Tests assert on the arguments each stub received. Real Docker, MySQL and root are never touched.

- Confirm-gated actions: `-y` runs, `n` aborts, `y` runs.
- Drift tests: every action has a `JACK_DOC_`, and aliases are unique across themes.
- Actions needing the real OS (`mount`, `flush-dns`) get stub-only coverage. CI on both OSes is out of scope.
