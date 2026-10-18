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
jack clean list         # which cleanups can run on this machine
jack clean pip          # purge one cache
jack clean all [-y]     # run every available cleanup
jack cheat list [theme] # every action with its description
jack help               # same as jack
jack --version          # print the version
jack port kill -h       # doc and usage for one action
```

Themes: `port`, `docker`, `mac`, `ubuntu`, `clean`, `cheat`, `completion`, `tuin`.

Action names use hyphens on the command line and underscores in code, so `jack mac flush-dns` runs `mac_flush_dns`. Destructive actions prompt and accept `-y`. Actions that need root exit with the `sudo jack ...` line to run, jack never calls sudo itself.

### Completion

```bash
command -v jack >/dev/null && eval "$(jack completion zsh)"
```

Use `bash` instead of `zsh` in `.bashrc`. In `.zshrc`, put the line after `compinit`, otherwise nothing registers.

### tuin (optional)

Run bare `jack` in a terminal and it offers once to enable [tuin](https://github.com/ikidnapmyself/tuin). Saying yes downloads a pinned, checksum-verified `tuin.sh` into `lib/vendor/` and turns on arrow-key confirm prompts, spinners for cleanups and an interactive theme and action picker on bare `jack`. Saying no never asks again. Change your mind any time with `jack tuin enable`, `jack tuin disable` or `jack tuin status`. The choice lives in `~/.config/jack/tuin` as `on` or `off`. Without it jack behaves as before.

### Clean

`jack clean` mirrors the remedies suggested by the disk checkers in [server-monitoring](https://github.com/ikidnapmyself/server-monitoring/tree/main/apps/checkers/checkers/disk). `jack clean all` skips gradle, maven and cargo, and prints the `sudo jack clean ...` line for actions that need root.

## Add a theme

Create `lib/<theme>.sh` with a `JACK_DESC="..."` line and functions named `<theme>_<action>`. Prefix helpers with `_<theme>_`. Every action needs a `JACK_DOC_<action>="one line"` and a `JACK_USAGE_<action>="args"` assignment. Use an empty usage for actions without arguments. Error messages should call `jack_usage <theme> <action>` instead of repeating the string. Values must not contain double quotes. Tests fail when a doc or usage is missing. Nothing else needs editing.

## Test

```bash
brew install bats-core
bats tests/
```
