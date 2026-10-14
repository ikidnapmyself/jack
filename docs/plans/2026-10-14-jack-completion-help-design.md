# jack: shell completion and help menu

## Goal

Tab completion for zsh and bash, plus `help` and `-h` at every level. Jack stays the single source of truth, so completion and help cannot drift from the code.

## Decisions

- Completion is generated, not a static file. Users add `command -v jack >/dev/null && eval "$(jack completion zsh)"` to their rc. New themes and actions need no edits elsewhere.
- Usage text moves into metadata. Each action declares `JACK_USAGE_<action>="..."` next to its `JACK_DOC`. Inline `die_usage "usage: ..."` strings read the same value, so usage lives in one place.
- Help is intercepted by the dispatcher. A literal `-h`, `--help` or `help` argument never reaches an action. No current action uses these.
- Supported shells are zsh and bash. Anything else exits 2 with a usage line.

## Metadata

`JACK_USAGE_<action>` holds the argument part only, for example `JACK_USAGE_kill="<port> [-y]"`. Help renders `usage: jack <theme> <action> <value>`. An action with no arguments uses an empty string. Values must not contain double quotes, same rule as `JACK_DOC`.

`jack_meta` already reads these with `sed`, so no new helper is needed beyond a small usage renderer in `lib/core.sh`.

## Dispatch

`bin/jack` changes:

- `jack help` and `jack -h` list themes, as today.
- `jack <theme> help` lists actions, as `jack <theme>` does today.
- `jack <theme> <action> -h|--help|help` prints the doc line, then the usage line, and exits 0 before the action runs.
- `jack __complete <words...>` is the hidden helper used by completion scripts. It prints candidates, one per line.

## Completion

New theme file `lib/completion.sh` with one action, `completion <zsh|bash>`. It prints a script that calls `jack __complete` at tab time.

`__complete` by word position:

- Position 1: theme names plus `help`.
- Position 2: action names for the theme, hyphenated, plus `help`.
- Later positions: nothing. File and flag completion fall back to the shell default.

zsh output pairs each action with its `JACK_DOC` as the description. bash output is names only.

`__complete` validates the theme with the same `[a-z]` check as the dispatcher and prints nothing on an unknown theme. It never errors, so a bad word cannot spam the terminal.

## Errors

- Unknown shell for `jack completion`: exit 2, `usage: jack completion <zsh|bash>`.
- Unknown theme or action in help: same `unknown theme` and `unknown action` messages as today.

## Tests

- Meta test: every action has a `JACK_USAGE`.
- Help: `-h`, `--help` and `help` print doc and usage and exit 0 for a sample action. The action body does not run.
- `__complete`: output at positions 1 and 2, unknown theme prints nothing, hyphenated action names.
- `completion zsh` and `completion bash` print non-empty scripts that pass `zsh -n` and `bash -n`. Unknown shell exits 2.

## Docs

README gets the completion eval line with the `command -v` guard, and the `JACK_USAGE` requirement in the Add a theme section.

## Out of scope

Flag completion, per-argument completion such as listening ports for `port kill`, fish.
