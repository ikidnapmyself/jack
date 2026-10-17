# server-monitoring opt-in design

## Goal

Let `ikidnapmyself/server-monitoring` offer jack as an optional toolbox. Nothing breaks when jack is missing, and the operator is never asked twice. Both tools run on the same machine.

## Decisions

- Direction: server-monitoring uses jack. Jack never imports anything from server-monitoring.
- Mechanism: detect `jack` on PATH and shell out. No vendored copy, no JSON plugin contract.
- Disk remedy hint: local only. It lives in the shell CLI (`bin/cli/`), never in alert text.
- Status: jack never reports status. A fresh check clears the alert.
- Timeline: every remedy is recorded on the incident timeline.
- Surfaces: install-time offer, a Tools menu in `sm-cli`, disk remedies, `jack port` and `jack docker`.

## Rejected approaches

| Approach | Why not |
|---|---|
| Vendor a pinned jack, like `bin/lib/tuin_vendor.sh` | Heavy for a multi-file tool and duplicates jack inside the repo. |
| Plugin contract with `jack --list-json` | Over-built for now. Jack has no JSON output. |

## Opt-in state

`~/.config/server-monitoring/jack` holds `on` or `off`. Absent means unset.

`install.sh` behavior:

| Situation | Result |
|---|---|
| State already set | Skip. |
| `--yes` | Install jack if missing, store `on`. |
| Non-interactive, no `--yes` | Skip, leave unset so a later interactive run can ask. |
| Interactive, jack missing | Offer to install, store the answer. |
| Interactive, jack present | Store `on`. |

`--yes` and `--json` remove roadblocks for automated integration. `--json` never prompts.

The Tools menu in `sm-cli` and the remedy hints show only when the state is `on` and `jack` is on PATH. Otherwise the existing raw commands run.

## Remedy flow

After the operator confirms a remedy, `sm-cli` runs these steps in order:

1. Run `jack clean <target>` and capture the exit code.
2. Run `record_remedy`. It runs on failure too, because a failed attempt belongs on the timeline.
3. Run `run_check <checker>`. This is the only step that can clear the alert and roll up the incident.
4. Agent: run `push_to_hub`. Hub: run `push_to_hub --local`.

The hub sees the alert clear through `/alerts/webhook/cluster/`. Nothing new is needed on the jack side.

## record_remedy

A new management command in `apps/alerts`, next to `push_to_hub`.

| Flag | Meaning |
|---|---|
| `--incident <id>` | Target one incident. |
| `--checker <name>` | Find the open incident for this checker on this instance. |
| `--command <text>` | The command that ran, such as `jack clean pip`. |
| `--exit-code <n>` | Exit status of the remedy. |
| `--operator <name>` | Who ran it. |
| `--json` | Print the result as JSON instead of text. |

Storage reuses `AlertHistory`, so no migration. One row per affected alert:

- `event`: `remedy_run`
- `details`: `{"tool": "jack", "command": "...", "exit_code": 0, "operator": "..."}`
- `old_status` and `new_status`: empty, because the follow-up check changes status.

JSON output:

```json
{
  "incident_id": 42,
  "alerts_recorded": 1,
  "entries": [{"history_id": 913, "alert_id": 77, "event": "remedy_run"}]
}
```

No open incident is not an error. The command exits 0 and reports `alerts_recorded: 0`.

`build_incident_timeline` gets one change so a `remedy_run` row reads "ran jack clean pip (exit 0) by burak".

## Version check

`sm-cli` runs `jack --version` and hides jack features when the version is below the minimum. Jack has no `--version` flag yet, so adding it is a small change in this repo.

## Testing

- Stub `jack` on PATH in bats, the same way other tools are stubbed.
- Cover each row of the `install.sh` table, including state already set.
- Django tests for `record_remedy`: one row per alert, `--json` shape, no open incident, failed exit code recorded.
- Timeline test for the `remedy_run` label.

## Open items

- The hub does not receive the remedy entry. `push_to_hub` sends alert state only, so carrying remedies across needs a cluster payload change. Left out for now.
- The console incident page reads extra keys from timeline entries. Check how it renders `remedy_run` before implementing.
