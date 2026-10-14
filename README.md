# jack

Local dev toolkit. `jack <theme> <action> [args]`.

## Install

```bash
ln -s "$PWD/bin/jack" /usr/local/bin/jack
```

## Use

```bash
jack                    # list themes
jack port               # list actions with descriptions
jack port list [port]
jack port kill <port> [-y]
jack cheat list [theme] # every action with its description
jack alias print        # alias lines for aliased actions
jack help               # same as jack
jack port kill -h       # doc and usage for one action
```

Themes: `port`, `docker`, `git`, `npm`, `mysql`, `mac`, `ubuntu`, `cheat`, `alias`, `completion`.

Action names use hyphens on the command line and underscores in code, so `jack mac flush-dns` runs `mac_flush_dns`. Destructive actions prompt and accept `-y`. Actions that need root exit with the `sudo jack ...` line to run, jack never calls sudo itself.

### Aliases

```bash
eval "$(jack alias print)"
```

Add that line to `.zshrc` or `.bashrc`.

### Completion

```bash
command -v jack >/dev/null && eval "$(jack completion zsh)"
```

Use `bash` instead of `zsh` in `.bashrc`. In `.zshrc`, put the line after `compinit`, otherwise nothing registers.

## Add a theme

Create `lib/<theme>.sh` with a `JACK_DESC="..."` line and functions named `<theme>_<action>`. Prefix helpers with `_<theme>_`. Every action needs a `JACK_DOC_<action>="one line"` and a `JACK_USAGE_<action>="args"` assignment, and may add `JACK_ALIAS_<action>="name"`. Use an empty usage for actions without arguments. Error messages should call `jack_usage <theme> <action>` instead of repeating the string. Values must not contain double quotes. Tests fail when a doc or usage is missing or an alias repeats. Nothing else needs editing.

## Test

```bash
brew install bats-core
bats tests/
```
