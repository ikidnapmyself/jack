# Security Policy

## Supported versions

Only the latest release and the `main` branch get security fixes.

## Reporting a vulnerability

Don't open a public issue. Use GitHub private vulnerability reporting:
the repository's Security tab, then "Report a vulnerability".

Include the jack version (`jack --version`), your OS, the command you ran
and what you expected to happen. A minimal reproduction helps most.

Expect an acknowledgement within a few days. Fixes ship on `main` first and
the advisory is published once a fix is available.

## Scope

In scope:
- Commands that delete, mount or restart things beyond what the user confirmed.
- Code execution through environment variables, config files or filenames.
- Privilege escalation when running under `sudo`.
- Integrity of downloaded code, currently the pinned tuin release.

Out of scope:
- Actions that work as documented after you confirm them, for example
  `jack ubuntu big-files-delete` removing the files it listed.
- Anything that needs write access to the jack install directory or to the
  invoking user's own config, unless it escalates privileges.

## Security model

- Destructive actions ask for confirmation. `-y` skips the prompt and is meant
  for scripts you've already reviewed.
- Actions that need root print the exact `sudo` command instead of escalating.
- The optional tuin UI is downloaded from a tagged release, checked against a
  pinned SHA256 at install and checked again on every load. If the checksum
  doesn't match, jack doesn't load it.
- When running as root, a `JACK_TUIN_FILE` override is ignored.
- `cargo-cache` is installed with a pinned version and `--locked`.
