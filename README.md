# jack

Local dev toolkit. `jack <theme> <action> [args]`.

## Install

```bash
ln -s "$PWD/bin/jack" /usr/local/bin/jack
```

## Use

```bash
jack                    # list themes
jack port               # list actions
jack port list [port]
jack port kill <port> [-y]
```

## Add a theme

Create `lib/<theme>.sh` with a `JACK_DESC="..."` line and functions named `<theme>_<action>`. Prefix helpers with `_<theme>_`. Nothing else needs editing.

## Test

```bash
brew install bats-core
bats tests/
```
