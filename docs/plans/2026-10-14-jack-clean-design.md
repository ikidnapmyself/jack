# jack clean design

## Goal

Let a user run the cleanup remedies that the server-monitoring disk checkers suggest, from one command: `jack clean <target>`. Source of the remedies is `apps/checkers/checkers/disk/recommendations.py` in `ikidnapmyself/server-monitoring`. Both tools run on the same machine.

## Scope

A new theme, `clean`, in `lib/clean.sh` with `JACK_DESC="Cache and disk cleanup"`.

Actions with a runnable command in the upstream rules:

| Action | Command | Notes |
|---|---|---|
| pip | `pip cache purge` | |
| yarn | `yarn cache clean` | |
| pnpm | `pnpm store prune` | |
| composer | `composer clear-cache` | |
| go | `go clean -modcache` | |
| brew | `brew cleanup --prune=all` | macOS |
| xcode | `rm -rf ~/Library/Developer/Xcode/DerivedData` | macOS, prompts |
| apt | `apt clean` | Linux, root |
| journal | `journalctl --vacuum-size=100M` | Linux, root |
| snap | remove disabled snap revisions | Linux, root, prompts |
| gradle | stop daemon, delete old cache versions | prompts, excluded from `all` |
| maven | purge local repository | prompts, excluded from `all` |
| cargo | install `cargo-cache`, then autoclean | prompts, excluded from `all` |
| npm | delegates to `npm_cache_clear` | no duplicate logic |
| docker | delegates to `docker_prune` | no duplicate logic |

Not included because upstream gives advice, not a command: JetBrains caches, `~/Library/Caches`, `~/.cache`, `/var/log` rotation.

## Behavior

- Follows existing conventions: `JACK_DOC_`, `JACK_USAGE_`, `JACK_OS`, `require_cmd`, `require_root`, `die_usage`, `jack_usage`.
- Root-only actions exit with the `sudo jack clean ...` line, jack never calls sudo.
- Destructive actions prompt and accept `-y`.
- A missing tool prints a clear message and exits non-zero.
- `jack clean list` shows each action, its description, and whether its tool is installed. No sizes in v1.
- `jack clean all [-y]` runs every action whose tool is present, skips the rest with a one-line notice, and asks once up front unless `-y` is passed. It excludes gradle, maven and cargo. It skips root-only actions when not root and prints their `sudo jack clean ...` line.

## Testing

`tests/clean.bats`, using the stub-on-`PATH` pattern from `tests/test_helper.bash`.

- Per action: the right command runs, a missing tool fails clearly, root-only actions refuse without root.
- `all`: skip behavior, root-only handling, and the `-y` path.
- `meta.bats` already enforces doc and usage strings.

## Later

- Upstream PR adding a stable `fix_id` per recommendation in server-monitoring, with jack actions keyed by id.
- `jack fix` that reads `manage.py check_health --json` and maps recommendations to `jack clean` actions through an interactive picker.
- Size reporting in `jack clean list`.
- Advice-only remedies: JetBrains, app caches, `~/.cache`, log rotation.
- Server-monitoring checkers using jack's features, with jack as an optional executor so monitored hosts don't require it.
