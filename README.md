# jack

```
     _            _
    | | __ _  ___| | __
 _  | |/ _` |/ __| |/ /
| |_| | (_| | (__|   <
 \___/ \__,_|\___|_|\_\
```

Local dev toolkit. `jack <theme> <action> [args]`.

## Install

Needs bash 3.2 or newer and git.

```bash
curl -fsSL https://raw.githubusercontent.com/ikidnapmyself/jack/main/install.sh | sh
```

Or with wget:

```bash
wget -qO- https://raw.githubusercontent.com/ikidnapmyself/jack/main/install.sh | sh
```

The script clones jack into `~/.local/share/jack` and links `~/.local/bin/jack`. It never uses sudo and never edits your shell rc. If `~/.local/bin` isn't on your `PATH`, or you want completion, it prints the line to add. Read [install.sh](install.sh) first if you'd rather not pipe to `sh`.

Run the same command again to update. Uninstall with:

```bash
curl -fsSL https://raw.githubusercontent.com/ikidnapmyself/jack/main/install.sh | sh -s -- --uninstall
```

Uninstalling leaves `~/.config/jack` in place.

Override the defaults with environment variables on the `sh` side of the pipe:

| Variable | Default |
| --- | --- |
| `JACK_DIR` | `~/.local/share/jack` |
| `JACK_BIN_DIR` | `~/.local/bin` |
| `JACK_REF` | `main` |
| `JACK_REPO` | `https://github.com/ikidnapmyself/jack.git` |

For a system-wide install, `curl -fsSL .../install.sh | sudo JACK_DIR=/opt/jack JACK_BIN_DIR=/usr/local/bin sh`.

### Manual install

```bash
git clone https://github.com/ikidnapmyself/jack.git ~/.local/share/jack
mkdir -p ~/.local/bin
ln -s ~/.local/share/jack/bin/jack ~/.local/bin/jack
```

Update with `git -C ~/.local/share/jack pull`. Check it worked with `jack --version`.

### Install with an AI agent

Paste this into Claude Code, Cursor or any coding agent with shell access:

```text
Install jack, a bash dev toolkit, from https://github.com/ikidnapmyself/jack.

1. Read https://raw.githubusercontent.com/ikidnapmyself/jack/main/install.sh
   and tell me in two lines what it does before running anything.
2. Run: curl -fsSL https://raw.githubusercontent.com/ikidnapmyself/jack/main/install.sh | sh
3. If the installer says ~/.local/bin isn't on my PATH, add the export line
   it printed to my shell rc. Detect the shell from $SHELL. Don't add it twice.
4. Add tab completion to the same rc file:
   command -v jack >/dev/null && eval "$(jack completion <zsh|bash>)"
   In .zshrc it must go after compinit. Skip it if it's already there.
5. Verify in a fresh shell: run `jack --version` and `jack`.
6. Show me the diff of every rc file you touched.

Don't use sudo. Don't run `jack tuin enable` or any destructive jack action.
Tell me I can turn on the optional tuin UI later with `jack tuin enable`.
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
jack cron list [count]  # crontab jobs with next run times
jack cron logs [n] [lines] # job log files, or one job's log
jack mem swap           # swap and RAM use with a verdict
jack mem usage          # total, used and available RAM
jack mem top [count]    # programs using the most memory
jack cheat list [theme] # every action with its description
jack help               # same as jack
jack --version          # print the version
jack port kill -h       # doc and usage for one action
```

Themes: `port`, `docker`, `mac`, `ubuntu`, `clean`, `cron`, `mem`, `cheat`, `completion`, `tuin`.

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

Create `lib/<theme>.sh` with a `JACK_DESC="..."` line and functions named `<theme>_<action>`. Prefix helpers with `_<theme>_`. Every action needs a `JACK_DOC_<action>="one line"` and a `JACK_USAGE_<action>="args"` assignment. Use an empty usage for actions without arguments. Error messages should call `jack_usage <theme> <action>` instead of repeating the string. Add `JACK_ASK_<action>="no"` to stop the tuin menu from prompting for optional arguments of that action. Required arguments with a `_<theme>_pick_<action>` helper open a filterable list instead of a text prompt. Values must not contain double quotes. Tests fail when a doc or usage is missing. Nothing else needs editing.

## Test

```bash
brew install bats-core
bats tests/
```
