# server-monitoring opt-in Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Let server-monitoring offer jack as an opt-in toolbox, and record every jack remedy on the incident timeline.

**Architecture:** server-monitoring detects `jack` on PATH and shells out to it. The opt-in answer lives in `~/.config/server-monitoring/jack`. A new `record_remedy` management command writes one `AlertHistory` row per affected alert. A fresh `run_check` is the only thing that clears an alert, and `push_to_hub` forwards the result.

**Tech Stack:** Bash and bats (jack, server-monitoring CLI), Django 5.2 and pytest (server-monitoring).

Design: `docs/plans/2026-10-17-server-monitoring-opt-in-design.md`.

**Repos.** Task 1 runs in `/Users/burak/Projects/jack-all-trades`. Tasks 2 to 8 run in `/Users/burak/Projects/server-maintanence`, the checkout of `ikidnapmyself/server-monitoring`. Paths below are relative to the repo named in each task.

**Assumptions to confirm before Task 5.**
- Jack installs by cloning `https://github.com/ikidnapmyself/jack-all-trades.git` into `~/.local/share/jack` and symlinking `bin/jack` into `~/.local/bin`. The URL is overridable with `JACK_REPO_URL`.
- Jack's first versioned release is `0.1.0`, which is also the minimum version server-monitoring accepts.

---

### Task 0: Isolated branch for server-monitoring

The checkout is on `feat/console-runs` with untracked files. Do not build on it.

**Step 1: Create a worktree from main**

Run: `git -C /Users/burak/Projects/server-maintanence worktree add ../server-maintanence-jack -b feat/jack-opt-in main`
Expected: `Preparing worktree (new branch 'feat/jack-opt-in')`

Tasks 2 to 8 run in `/Users/burak/Projects/server-maintanence-jack`.

**Step 2: Install dependencies**

Run: `cd /Users/burak/Projects/server-maintanence-jack && uv sync`
Expected: exits 0.

**Step 3: Confirm a green baseline**

Run: `uv run pytest apps/alerts -q`
Expected: all pass. If anything fails here, stop and report it.

---

### Task 1: `jack --version` (jack repo)

**Files:**
- Modify: `lib/core.sh:27` (add the constant next to `JACK_TUIN_VERSION`)
- Modify: `bin/jack` (`main`, right after the `__complete` branch)
- Test: `tests/dispatch.bats`
- Modify: `README.md` (usage block)

**Step 1: Write the failing test**

Append to `tests/dispatch.bats`:

```bash
@test "--version prints the jack version" {
  run "$JACK" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^jack\ [0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "--version is not treated as a theme" {
  run "$JACK" --version
  [[ "$output" != *"unknown theme"* ]]
}
```

**Step 2: Run it to verify it fails**

Run: `bats tests/dispatch.bats -f "version"`
Expected: FAIL, output contains `unknown theme: --version`.

**Step 3: Implement**

In `lib/core.sh`, add above the `JACK_TUIN_VERSION` line:

```bash
JACK_VERSION="0.1.0"
```

In `bin/jack`, inside `main`, after the `__complete` block:

```bash
  if [ "$theme" = --version ]; then
    echo "jack $JACK_VERSION"
    return 0
  fi
```

In `README.md`, add to the `## Use` code block after `jack help`:

```bash
jack --version          # print the version
```

**Step 4: Run the full suite**

Run: `bats tests/`
Expected: all pass.

**Step 5: Commit**

```bash
git add lib/core.sh bin/jack tests/dispatch.bats README.md
git commit -m "feat: add --version flag"
```

---

### Task 2: Remedy service (server-monitoring)

**Files:**
- Create: `apps/alerts/remedies.py`
- Test: `apps/alerts/_tests/test_remedies.py`

**Step 1: Write the failing test**

Create `apps/alerts/_tests/test_remedies.py`:

```python
from unittest.mock import patch

from django.test import TestCase
from django.utils import timezone

from apps.alerts.identity import checker_fingerprint
from apps.alerts.models import Alert, AlertHistory, Incident, IncidentStatus
from apps.alerts.remedies import (
    REMEDY_EVENT,
    alerts_for_checker,
    alerts_for_incident,
    record_remedy,
)

INSTANCE = "web-01"


class RemedyServiceTests(TestCase):
    def setUp(self):
        patcher = patch("apps.alerts.remedies.local_instance_id", return_value=INSTANCE)
        patcher.start()
        self.addCleanup(patcher.stop)

    def _alert(self, incident, *, checker="disk", instance=INSTANCE, status="firing"):
        return Alert.objects.create(
            fingerprint=checker_fingerprint(instance, checker),
            source="cluster",
            name=f"{checker} high",
            status=status,
            started_at=timezone.now(),
            incident=incident,
            labels={"checker": checker},
        )

    def test_alerts_for_checker_finds_firing_alert_in_open_incident(self):
        incident = Incident.objects.create()
        alert = self._alert(incident)
        assert alerts_for_checker("disk") == [alert]

    def test_alerts_for_checker_includes_acknowledged_incident(self):
        incident = Incident.objects.create(status=IncidentStatus.ACKNOWLEDGED)
        alert = self._alert(incident)
        assert alerts_for_checker("disk") == [alert]

    def test_alerts_for_checker_ignores_resolved_incident(self):
        incident = Incident.objects.create(status=IncidentStatus.RESOLVED)
        self._alert(incident)
        assert alerts_for_checker("disk") == []

    def test_alerts_for_checker_ignores_other_instance(self):
        incident = Incident.objects.create()
        self._alert(incident, instance="db-02")
        assert alerts_for_checker("disk") == []

    def test_alerts_for_incident_returns_only_firing_alerts(self):
        incident = Incident.objects.create()
        firing = self._alert(incident, checker="disk")
        self._alert(incident, checker="cpu", status="resolved")
        assert alerts_for_incident(incident.pk) == [firing]

    def test_record_remedy_writes_one_row_per_alert(self):
        incident = Incident.objects.create()
        first = self._alert(incident, checker="disk")
        second = self._alert(incident, checker="cpu")

        rows = record_remedy(
            [first, second], command="jack clean pip", exit_code=0, operator="burak"
        )

        assert len(rows) == 2
        row = AlertHistory.objects.get(alert=first)
        assert row.event == REMEDY_EVENT
        assert row.old_status == ""
        assert row.new_status == ""
        assert row.details == {
            "tool": "jack",
            "command": "jack clean pip",
            "exit_code": 0,
            "operator": "burak",
        }

    def test_record_remedy_with_no_alerts_writes_nothing(self):
        assert record_remedy([], command="jack clean pip", exit_code=0, operator="") == []
        assert AlertHistory.objects.count() == 0
```

**Step 2: Run it to verify it fails**

Run: `uv run pytest apps/alerts/_tests/test_remedies.py -q`
Expected: FAIL with `ModuleNotFoundError: No module named 'apps.alerts.remedies'`.

**Step 3: Write minimal implementation**

Create `apps/alerts/remedies.py`:

```python
from apps.alerts.identity import checker_fingerprint, local_instance_id
from apps.alerts.models import Alert, AlertHistory, AlertStatus, IncidentStatus

REMEDY_EVENT = "remedy_run"
REMEDY_TOOL = "jack"
OPEN_INCIDENT_STATUSES = (IncidentStatus.OPEN, IncidentStatus.ACKNOWLEDGED)


def alerts_for_checker(checker: str) -> list[Alert]:
    return list(
        Alert.objects.filter(
            fingerprint=checker_fingerprint(local_instance_id(), checker),
            status=AlertStatus.FIRING,
            incident__status__in=OPEN_INCIDENT_STATUSES,
        )
    )


def alerts_for_incident(incident_id: int) -> list[Alert]:
    return list(Alert.objects.filter(incident_id=incident_id, status=AlertStatus.FIRING))


def record_remedy(
    alerts: list[Alert], *, command: str, exit_code: int, operator: str
) -> list[AlertHistory]:
    details = {
        "tool": REMEDY_TOOL,
        "command": command,
        "exit_code": exit_code,
        "operator": operator,
    }
    return [
        AlertHistory.objects.create(alert=alert, event=REMEDY_EVENT, details=dict(details))
        for alert in alerts
    ]
```

**Step 4: Run it to verify it passes**

Run: `uv run pytest apps/alerts/_tests/test_remedies.py -q`
Expected: 7 passed.

**Step 5: Commit**

```bash
git add apps/alerts/remedies.py apps/alerts/_tests/test_remedies.py
git commit -m "feat(alerts): add remedy recording service"
```

---

### Task 3: `record_remedy` command with `--json`

**Files:**
- Create: `apps/alerts/management/commands/record_remedy.py`
- Test: `apps/alerts/_tests/commands/test_record_remedy.py`

**Step 1: Write the failing test**

Create `apps/alerts/_tests/commands/test_record_remedy.py`:

```python
import json
from io import StringIO
from unittest.mock import patch

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase
from django.utils import timezone

from apps.alerts.identity import checker_fingerprint
from apps.alerts.models import Alert, AlertHistory, Incident

INSTANCE = "web-01"


class RecordRemedyCommandTests(TestCase):
    def setUp(self):
        patcher = patch("apps.alerts.remedies.local_instance_id", return_value=INSTANCE)
        patcher.start()
        self.addCleanup(patcher.stop)

    def _disk_alert(self):
        incident = Incident.objects.create()
        alert = Alert.objects.create(
            fingerprint=checker_fingerprint(INSTANCE, "disk"),
            source="cluster",
            name="disk high",
            status="firing",
            started_at=timezone.now(),
            incident=incident,
            labels={"checker": "disk"},
        )
        return incident, alert

    def _run(self, *args):
        out = StringIO()
        call_command("record_remedy", *args, stdout=out)
        return out.getvalue()

    def test_checker_target_json_output(self):
        incident, alert = self._disk_alert()

        output = self._run(
            "--checker", "disk",
            "--command", "jack clean pip",
            "--exit-code", "0",
            "--operator", "burak",
            "--json",
        )

        row = AlertHistory.objects.get(alert=alert)
        assert json.loads(output) == {
            "incident_id": incident.pk,
            "alerts_recorded": 1,
            "entries": [{"history_id": row.pk, "alert_id": alert.pk, "event": "remedy_run"}],
        }

    def test_incident_target_text_output(self):
        incident, _ = self._disk_alert()

        output = self._run(
            "--incident", str(incident.pk),
            "--command", "jack clean pip",
            "--exit-code", "1",
        )

        assert "Recorded remedy on 1 alert(s)." in output
        assert AlertHistory.objects.filter(details__exit_code=1).count() == 1

    def test_no_open_incident_is_not_an_error(self):
        output = self._run(
            "--checker", "disk",
            "--command", "jack clean pip",
            "--exit-code", "0",
            "--json",
        )

        assert json.loads(output) == {
            "incident_id": None,
            "alerts_recorded": 0,
            "entries": [],
        }

    def test_unknown_incident_errors(self):
        with self.assertRaises(CommandError) as ctx:
            self._run("--incident", "999", "--command", "x", "--exit-code", "0")
        assert "999" in str(ctx.exception)

    def test_target_is_required(self):
        with self.assertRaises(CommandError):
            self._run("--command", "x", "--exit-code", "0")

    def test_does_not_change_alert_status(self):
        _, alert = self._disk_alert()
        self._run("--checker", "disk", "--command", "x", "--exit-code", "0")
        alert.refresh_from_db()
        assert alert.status == "firing"
```

**Step 2: Run it to verify it fails**

Run: `uv run pytest apps/alerts/_tests/commands/test_record_remedy.py -q`
Expected: FAIL with `CommandError: Unknown command: 'record_remedy'`.

**Step 3: Write minimal implementation**

Create `apps/alerts/management/commands/record_remedy.py`:

```python
"""
Record on the incident timeline that an operator ran a remedy.

Usage:
    python manage.py record_remedy --checker disk --command "jack clean pip" --exit-code 0
    python manage.py record_remedy --incident 42 --command "jack clean pip" --exit-code 1 --json
"""

import json

from django.core.management.base import BaseCommand, CommandError

from apps.alerts.models import Incident
from apps.alerts.remedies import (
    REMEDY_EVENT,
    alerts_for_checker,
    alerts_for_incident,
    record_remedy,
)


class Command(BaseCommand):
    help = (
        "Record that an operator ran a remedy against an incident's firing alerts. "
        "Never changes alert status: a fresh check does that."
    )

    def add_arguments(self, parser):
        target = parser.add_mutually_exclusive_group(required=True)
        target.add_argument("--incident", type=int, help="Incident id.")
        target.add_argument(
            "--checker", help="Checker name. Targets this instance's open incident for it."
        )
        parser.add_argument(
            "--command", dest="remedy_command", required=True, help="Command that ran."
        )
        parser.add_argument("--exit-code", type=int, required=True, help="Remedy exit status.")
        parser.add_argument("--operator", default="", help="Who ran it.")
        parser.add_argument("--json", action="store_true", help="Print the result as JSON.")

    def handle(self, *args, **options):
        incident_id = options["incident"]
        if incident_id is not None:
            if not Incident.objects.filter(pk=incident_id).exists():
                raise CommandError(f"No incident with id {incident_id}")
            alerts = alerts_for_incident(incident_id)
        else:
            alerts = alerts_for_checker(options["checker"])

        rows = record_remedy(
            alerts,
            command=options["remedy_command"],
            exit_code=options["exit_code"],
            operator=options["operator"],
        )

        if options["json"]:
            result = {
                "incident_id": alerts[0].incident_id if alerts else incident_id,
                "alerts_recorded": len(rows),
                "entries": [
                    {"history_id": row.pk, "alert_id": row.alert_id, "event": REMEDY_EVENT}
                    for row in rows
                ],
            }
            self.stdout.write(json.dumps(result))
            return

        self.stdout.write(f"Recorded remedy on {len(rows)} alert(s).")
```

**Step 4: Run it to verify it passes**

Run: `uv run pytest apps/alerts/_tests/commands/test_record_remedy.py -q`
Expected: 6 passed.

**Step 5: Commit**

```bash
git add apps/alerts/management/commands/record_remedy.py apps/alerts/_tests/commands/test_record_remedy.py
git commit -m "feat(alerts): add record_remedy command with --json"
```

---

### Task 4: Render `remedy_run` on the timeline

**Files:**
- Modify: `apps/alerts/describing.py:26` (`HISTORY_TONES`) and `describe_history` at `:172`
- Modify: `apps/alerts/timeline.py:43-70` (the `AlertHistory` loop)
- Modify: `apps/console/queries/incident.py` (`_history_entry`)
- Test: `apps/alerts/_tests/test_describing.py`, `apps/alerts/_tests/test_timeline.py`

**Step 1: Write the failing tests**

Append to `apps/alerts/_tests/test_describing.py`, after `TestDescribeHistory`:

```python
class TestDescribeRemedy:
    def test_remedy_row_names_the_command_and_facts(self):
        description = describe_history(
            "remedy_run",
            alert_headline="Disk usage",
            old_status="",
            new_status="",
            severity_from=None,
            severity_to=None,
            remedy={"command": "jack clean pip", "exit_code": 0, "operator": "burak"},
        )
        assert description.headline == "Disk usage: ran jack clean pip"
        assert description.tone == "info"
        assert description.facts == (Fact("Exit code", "0"), Fact("Operator", "burak"))

    def test_remedy_row_without_details_still_reads(self):
        description = describe_history(
            "remedy_run",
            alert_headline="Disk usage",
            old_status="",
            new_status="",
            severity_from=None,
            severity_to=None,
        )
        assert description.headline == "Disk usage: ran a remedy"
        assert description.facts == ()
```

Add to `apps/alerts/_tests/test_timeline.py` inside `BuildIncidentTimelineTests`:

```python
    def test_remedy_row_carries_details_and_summary(self):
        incident = Incident.objects.create()
        alert = self._make_alert(incident, started_at=timezone.now())
        AlertHistory.objects.create(
            alert=alert,
            event="remedy_run",
            details={"tool": "jack", "command": "jack clean pip", "exit_code": 0, "operator": "burak"},
        )

        (entry,) = build_incident_timeline(incident)

        assert entry["label"] == "remedy_run"
        assert entry["detail"] == "jack clean pip (exit 0) by burak"
        assert entry["remedy"]["command"] == "jack clean pip"

    def test_non_remedy_rows_have_no_remedy_key_value(self):
        incident = Incident.objects.create()
        alert = self._make_alert(incident, started_at=timezone.now())
        AlertHistory.objects.create(alert=alert, event="created", new_status="firing")

        (entry,) = build_incident_timeline(incident)

        assert entry["remedy"] is None
```

**Step 2: Run them to verify they fail**

Run: `uv run pytest apps/alerts/_tests/test_describing.py apps/alerts/_tests/test_timeline.py -q`
Expected: FAIL, `describe_history() got an unexpected keyword argument 'remedy'` and `KeyError: 'remedy'`.

**Step 3: Implement**

In `apps/alerts/describing.py`:

Change `HISTORY_TONES` to:

```python
HISTORY_TONES = {"resolved": "ok", "created": "info", "refired": "info", "remedy_run": "info"}
```

Add above `describe_history`:

```python
def remedy_summary(details: Any) -> str:
    record = _dict(details)
    summary = _text(record.get("command")) or "a remedy"
    exit_code = record.get("exit_code")
    if isinstance(exit_code, int):
        summary = f"{summary} (exit {exit_code})"
    operator = _text(record.get("operator"))
    return f"{summary} by {operator}" if operator else summary


def _describe_remedy(alert_headline: str, details: Any) -> Description:
    record = _dict(details)
    command = _text(record.get("command")) or "a remedy"
    facts = tuple(
        Fact(label, str(value))
        for label, value in (
            ("Exit code", record.get("exit_code")),
            ("Operator", _text(record.get("operator"))),
        )
        if value not in (None, "")
    )
    return Description(
        headline=f"{alert_headline}: ran {command}",
        tone=history_tone("remedy_run", None),
        facts=facts,
    )
```

Change the `describe_history` signature and add the early return:

```python
def describe_history(
    event: str,
    *,
    alert_headline: str,
    old_status: str,
    new_status: str,
    severity_from: object,
    severity_to: object,
    remedy: Any = None,
) -> Description:
    if event == "remedy_run":
        return _describe_remedy(alert_headline, remedy)
    sev_from, sev_to = _text(severity_from), _text(severity_to)
    ...
```

In `apps/alerts/timeline.py`, import the helpers:

```python
from apps.alerts.describing import remedy_summary
```

If that import is circular, move `remedy_summary` and `_dict` use into `timeline.py` locally instead and report it. In the `AlertHistory` loop, after `detail = ", ".join(parts) or None`:

```python
        remedy = details if h.event == "remedy_run" else None
        if remedy is not None:
            detail = remedy_summary(remedy)
```

and add `"remedy": remedy,` to the entry dict next to `"event": h.event,`.

In `apps/console/queries/incident.py`, `_history_entry`, add the kwarg to the `describe_history` call:

```python
        severity_to=event["severity_to"],
        remedy=event.get("remedy"),
```

Also update the timeline docstring list of extra keys: add `remedy` to the `alert_history` keys.

**Step 4: Run the touched suites**

Run: `uv run pytest apps/alerts apps/console -q`
Expected: all pass.

**Step 5: Check it in the console**

Run: `uv run python manage.py runserver`, open an incident that has a `remedy_run` row (create one with `record_remedy` against a firing disk alert), and confirm the row reads "ran jack clean pip" with Exit code and Operator facts. Report if the console page needs a template change.

**Step 6: Commit**

```bash
git add apps/alerts apps/console
git commit -m "feat(alerts): show remedy runs on the incident timeline"
```

---

### Task 5: `bin/lib/jack.sh` state and install helpers

**Files:**
- Create: `bin/lib/jack.sh`
- Test: `bin/tests/lib/test_jack.bats`

**Step 1: Write the failing test**

Create `bin/tests/lib/test_jack.bats`:

```bash
#!/usr/bin/env bats

setup() {
    load '../test_helper/common-setup'
    _common_setup
    TEST_TMPDIR="$(mktemp -d)"
    export JACK_STATE_FILE="$TEST_TMPDIR/config/jack"
    export JACK_HOME="$TEST_TMPDIR/home/jack"
    export JACK_BIN_DIR="$TEST_TMPDIR/bin"
    STUB_DIR="$TEST_TMPDIR/stubs"
    mkdir -p "$STUB_DIR"
    PATH="$STUB_DIR:$PATH"
    source "$LIB_DIR/jack.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

stub_jack() {
    printf '#!/usr/bin/env bash\necho "jack %s"\n' "$1" > "$STUB_DIR/jack"
    chmod +x "$STUB_DIR/jack"
}

make_jack_repo() {
    local repo="$TEST_TMPDIR/jack-repo"
    mkdir -p "$repo/bin"
    printf '#!/usr/bin/env bash\necho "jack 0.1.0"\n' > "$repo/bin/jack"
    chmod +x "$repo/bin/jack"
    git -C "$repo" init -q
    git -C "$repo" add -A
    git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m init
    export JACK_REPO_URL="$repo"
}

@test "jack.sh passes syntax check" {
    run bash -n "$LIB_DIR/jack.sh"
    assert_success
}

@test "jack_state is empty when the file is missing" {
    run jack_state
    assert_success
    assert_output ""
}

@test "jack_set_state round-trips" {
    jack_set_state on
    run jack_state
    assert_output "on"
}

@test "jack_version reads the second word of jack --version" {
    stub_jack "0.3.1"
    run jack_version
    assert_output "0.3.1"
}

@test "jack_version fails when jack is missing" {
    run env PATH="/usr/bin:/bin" bash -c "source '$LIB_DIR/jack.sh'; jack_version"
    assert_failure
}

@test "jack_version_ok accepts the minimum and above" {
    stub_jack "0.1.0"
    run jack_version_ok
    assert_success
    stub_jack "0.10.0"
    run jack_version_ok
    assert_success
}

@test "jack_version_ok rejects an older version" {
    stub_jack "0.0.9"
    run jack_version_ok
    assert_failure
}

@test "jack_version_ok rejects a jack with no --version output" {
    printf '#!/usr/bin/env bash\nexit 2\n' > "$STUB_DIR/jack"
    chmod +x "$STUB_DIR/jack"
    run jack_version_ok
    assert_failure
}

@test "jack_enabled needs state on and a new enough jack" {
    stub_jack "0.1.0"
    run jack_enabled
    assert_failure
    jack_set_state off
    run jack_enabled
    assert_failure
    jack_set_state on
    run jack_enabled
    assert_success
}

@test "jack_install clones the repo and links the binary" {
    make_jack_repo
    run jack_install
    assert_success
    [ -x "$JACK_BIN_DIR/jack" ]
    run "$JACK_BIN_DIR/jack" --version
    assert_output "jack 0.1.0"
}

@test "jack_install fails when the clone fails" {
    export JACK_REPO_URL="$TEST_TMPDIR/missing"
    run jack_install
    assert_failure
    [ ! -e "$JACK_BIN_DIR/jack" ]
}
```

**Step 2: Run it to verify it fails**

Run: `./bin/tests/test_helper/bats-core/bin/bats bin/tests/lib/test_jack.bats`
Expected: FAIL, `jack.sh: No such file or directory`.

**Step 3: Write minimal implementation**

Create `bin/lib/jack.sh`:

```bash
#!/usr/bin/env bash

[[ -n "${_LIB_JACK_LOADED:-}" ]] && return 0
_LIB_JACK_LOADED=1

JACK_MIN_VERSION="${JACK_MIN_VERSION:-0.1.0}"
JACK_REPO_URL="${JACK_REPO_URL:-https://github.com/ikidnapmyself/jack-all-trades.git}"
JACK_HOME="${JACK_HOME:-$HOME/.local/share/jack}"
JACK_BIN_DIR="${JACK_BIN_DIR:-$HOME/.local/bin}"
JACK_STATE_FILE="${JACK_STATE_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/server-monitoring/jack}"

jack_state() {
    [[ -f "$JACK_STATE_FILE" ]] && cat "$JACK_STATE_FILE"
    return 0
}

jack_set_state() {
    mkdir -p "$(dirname "$JACK_STATE_FILE")" && printf '%s\n' "$1" > "$JACK_STATE_FILE"
}

jack_version() {
    command -v jack >/dev/null 2>&1 || return 1
    jack --version 2>/dev/null | awk '{print $2}'
}

jack_version_ok() {
    local have
    have="$(jack_version)" || return 1
    [[ -n "$have" ]] || return 1
    [[ "$(printf '%s\n%s\n' "$JACK_MIN_VERSION" "$have" | sort -V | head -n 1)" == "$JACK_MIN_VERSION" ]]
}

jack_enabled() {
    [[ "$(jack_state)" == "on" ]] && jack_version_ok
}

jack_install() {
    command -v git >/dev/null 2>&1 || { echo "git is required to install jack" >&2; return 1; }
    if [[ -d "$JACK_HOME/.git" ]]; then
        git -C "$JACK_HOME" pull --ff-only >&2 || return 1
    else
        git clone --depth 1 "$JACK_REPO_URL" "$JACK_HOME" >&2 || return 1
    fi
    mkdir -p "$JACK_BIN_DIR" && ln -sf "$JACK_HOME/bin/jack" "$JACK_BIN_DIR/jack"
}
```

**Step 4: Run it to verify it passes**

Run: `./bin/tests/test_helper/bats-core/bin/bats bin/tests/lib/test_jack.bats`
Expected: all pass. If `sort -V` is missing on the host, report it and stop.

**Step 5: Commit**

```bash
git add bin/lib/jack.sh bin/tests/lib/test_jack.bats
git commit -m "feat(bin): add jack state, version and install helpers"
```

---

### Task 6: Installer step `jack`

**Files:**
- Create: `bin/install/jack.sh`
- Modify: `bin/install.sh` (header comment steps list, `show_usage`, `run_all`, dispatcher)
- Test: `bin/tests/test_install_jack.bats`

**Step 1: Write the failing test**

Create `bin/tests/test_install_jack.bats`:

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    TEST_TMPDIR="$(mktemp -d)"
    export JACK_STATE_FILE="$TEST_TMPDIR/config/jack"
    export JACK_HOME="$TEST_TMPDIR/home/jack"
    export JACK_BIN_DIR="$TEST_TMPDIR/bin"
    REPO="$TEST_TMPDIR/jack-repo"
    mkdir -p "$REPO/bin"
    printf '#!/usr/bin/env bash\necho "jack 0.1.0"\n' > "$REPO/bin/jack"
    chmod +x "$REPO/bin/jack"
    git -C "$REPO" init -q
    git -C "$REPO" add -A
    git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m init
    export JACK_REPO_URL="$REPO"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

run_step() {
    run bash -c "source '$BIN_DIR/install/jack.sh'"
}

@test "install/jack.sh passes syntax check" {
    run bash -n "$BIN_DIR/install/jack.sh"
    assert_success
}

@test "state already set is left alone" {
    mkdir -p "$(dirname "$JACK_STATE_FILE")"
    echo off > "$JACK_STATE_FILE"
    INSTALL_AUTO_ACCEPT=1 run_step
    assert_success
    run cat "$JACK_STATE_FILE"
    assert_output "off"
    [ ! -e "$JACK_BIN_DIR/jack" ]
}

@test "--yes installs jack and stores on" {
    INSTALL_AUTO_ACCEPT=1 run_step
    assert_success
    [ -x "$JACK_BIN_DIR/jack" ]
    run cat "$JACK_STATE_FILE"
    assert_output "on"
}

@test "--yes with a failing install continues and leaves state unset" {
    export JACK_REPO_URL="$TEST_TMPDIR/missing"
    INSTALL_AUTO_ACCEPT=1 run_step
    assert_success
    [ ! -f "$JACK_STATE_FILE" ]
}

@test "non-interactive without --yes skips and leaves state unset" {
    INSTALL_AUTO_ACCEPT=0 run_step
    assert_success
    [ ! -f "$JACK_STATE_FILE" ]
    [ ! -e "$JACK_BIN_DIR/jack" ]
}

@test "install.sh lists the jack step in help" {
    run "$BIN_DIR/install.sh" help
    assert_output --partial "jack"
}
```

bats runs without a TTY, so the interactive branches are covered by the manual check in Task 8.

**Step 2: Run it to verify it fails**

Run: `./bin/tests/test_helper/bats-core/bin/bats bin/tests/test_install_jack.bats`
Expected: FAIL, `install/jack.sh: No such file or directory`.

**Step 3: Write the module**

Create `bin/install/jack.sh`:

```bash
#!/usr/bin/env bash

_INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LIB_DIR="$(cd "$_INSTALL_DIR/../lib" && pwd)"

source "$_LIB_DIR/logging.sh"
source "$_LIB_DIR/prompt.sh"
source "$_LIB_DIR/jack.sh"

_jack_enable() {
    if ! jack_install; then
        warn "jack install failed, continuing without it"
        return 0
    fi
    jack_set_state on
    info "jack is on"
    command -v jack >/dev/null 2>&1 || warn "add $JACK_BIN_DIR to PATH to use jack"
}

_jack_step() {
    [[ -z "$(jack_state)" ]] || return 0

    if [[ "${INSTALL_AUTO_ACCEPT:-0}" == "1" ]]; then
        _jack_enable
        return 0
    fi

    [[ -t 0 && -t 1 ]] || return 0

    if command -v jack >/dev/null 2>&1; then
        jack_set_state on
        return 0
    fi

    if prompt_yes_no "Install jack (optional toolbox for cleanups, ports and docker)?"; then
        _jack_enable
    else
        jack_set_state off
    fi
}

_jack_step
```

**Step 4: Register the step in `bin/install.sh`**

- Header comment: add `#   jack      Optional jack toolbox` after the `aliases` line.
- `show_usage`: add `echo "  jack      Optional jack toolbox (--yes installs it)"` after the `aliases` line.
- `run_all`: before the `Set up shell aliases?` block add:

```bash
    source "$INSTALL_MOD_DIR/jack.sh"
```

- Dispatcher: add `jack)     source "$INSTALL_MOD_DIR/jack.sh"     ;;` after the `aliases)` branch.

**Step 5: Run the installer tests**

Run: `./bin/tests/test_helper/bats-core/bin/bats bin/tests/test_install_jack.bats bin/tests/test_install.bats`
Expected: all pass.

**Step 6: Commit**

```bash
git add bin/install/jack.sh bin/install.sh bin/tests/test_install_jack.bats
git commit -m "feat(install): add opt-in jack step"
```

---

### Task 7: sm-cli Tools menu and remedy flow

**Files:**
- Create: `bin/cli/tools.sh`
- Modify: `bin/cli.sh` (sources, `main_menu_loop`)
- Modify: `bin/cli/health.sh` (menu items)
- Test: `bin/tests/test_tools.bats`

**Step 1: Write the failing test**

Create `bin/tests/test_tools.bats`:

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    TEST_TMPDIR="$(mktemp -d)"
    export PROJECT_DIR="$TEST_TMPDIR/project"
    mkdir -p "$PROJECT_DIR"
    export STUB_LOG="$TEST_TMPDIR/log"
    : > "$STUB_LOG"
    STUB_DIR="$TEST_TMPDIR/stubs"
    mkdir -p "$STUB_DIR"
    PATH="$STUB_DIR:$PATH"

    printf '#!/usr/bin/env bash\necho "uv $*" >> "$STUB_LOG"\n' > "$STUB_DIR/uv"
    chmod +x "$STUB_DIR/uv"
    export UV_BIN="$STUB_DIR/uv"

    source "$BIN_DIR/cli/tools.sh"
}

teardown() {
    rm -rf "$TEST_TMPDIR"
}

stub_jack() {
    local code="$1"
    cat > "$STUB_DIR/jack" <<EOF
#!/usr/bin/env bash
echo "jack \$*" >> "\$STUB_LOG"
if [ "\$1 \$2" = "clean list" ]; then
cat <<'LIST'
READY means the tool is installed and the action applies to this OS.

ACTION     READY  DESCRIPTION
pip        yes    Purge the pip cache
pnpm       no     Prune the pnpm store
npm        yes    Force-clear the npm cache
LIST
fi
exit $code
EOF
    chmod +x "$STUB_DIR/jack"
}

@test "tools.sh passes syntax check" {
    run bash -n "$BIN_DIR/cli/tools.sh"
    assert_success
}

@test "jack_cleanup_targets lists only ready actions" {
    stub_jack 0
    run jack_cleanup_targets
    assert_success
    assert_line --index 0 "pip"
    assert_line --index 1 "npm"
    refute_output --partial "pnpm"
    refute_output --partial "ACTION"
}

@test "run_remedy runs remedy, records, re-checks and forwards in order" {
    stub_jack 0
    run run_remedy disk pip
    assert_success
    run cat "$STUB_LOG"
    assert_line --index 0 "jack clean pip"
    assert_line --index 1 --partial "uv run python manage.py record_remedy --checker disk --command jack clean pip --exit-code 0"
    assert_line --index 2 "uv run python manage.py run_check disk"
    assert_line --index 3 "uv run python manage.py push_to_hub --local"
}

@test "run_remedy records a failed remedy and still re-checks" {
    stub_jack 3
    run run_remedy disk pip
    assert_failure 3
    run cat "$STUB_LOG"
    assert_line --index 1 --partial "--exit-code 3"
    assert_line --index 2 "uv run python manage.py run_check disk"
}

@test "run_remedy pushes to the hub when HUB_URL is set" {
    stub_jack 0
    echo "HUB_URL=https://hub.example.com" > "$PROJECT_DIR/.env"
    run run_remedy disk pip
    assert_success
    run cat "$STUB_LOG"
    assert_line --index 3 "uv run python manage.py push_to_hub"
}

@test "run_remedy survives a failing record step" {
    stub_jack 0
    printf '#!/usr/bin/env bash\necho "uv $*" >> "$STUB_LOG"\n[ "$4" = record_remedy ] && exit 1\nexit 0\n' > "$STUB_DIR/uv"
    run run_remedy disk pip
    assert_success
    run cat "$STUB_LOG"
    assert_line --index 2 "uv run python manage.py run_check disk"
}
```

**Step 2: Run it to verify it fails**

Run: `./bin/tests/test_helper/bats-core/bin/bats bin/tests/test_tools.bats`
Expected: FAIL, `cli/tools.sh: No such file or directory`.

**Step 3: Write `bin/cli/tools.sh`**

```bash
# shellcheck shell=bash
# Sourced by cli.sh — do not execute directly.

_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_TOOLS_DIR/../lib/dotenv.sh"
source "$_TOOLS_DIR/../lib/jack.sh"

jack_cleanup_targets() {
    jack clean list 2>/dev/null | awk '$2 == "yes" && $1 != "ACTION" {print $1}'
}

jack_themes() {
    jack 2>/dev/null | awk '/^themes:/ {found = 1; next} found && NF {print $1}'
}

forward_to_hub() {
    local -a args=()
    dotenv_has_value "$PROJECT_DIR/.env" "HUB_URL" || args+=(--local)
    "$UV_BIN" run python manage.py push_to_hub ${args[@]+"${args[@]}"}
}

run_remedy() {
    local checker="$1" target="$2" code=0
    jack clean "$target" || code=$?
    "$UV_BIN" run python manage.py record_remedy --checker "$checker" \
        --command "jack clean $target" --exit-code "$code" --operator "${USER:-}" || true
    "$UV_BIN" run python manage.py run_check "$checker" || true
    forward_to_hub || true
    return "$code"
}

disk_remedy_menu() {
    local -a targets=()
    local line target
    while IFS= read -r line; do
        [ -n "$line" ] && targets+=("$line")
    done < <(jack_cleanup_targets)
    if [ "${#targets[@]}" -eq 0 ]; then
        echo -e "${RED}No cleanups available on this machine${NC}"
        return 0
    fi
    if target=$(pick_or_cancel "Select a cleanup" "${targets[@]}"); then
        tuin_section "Command to run"
        echo -e "  ${CYAN}jack clean $target${NC}"
        if tuin_confirm "Run, record, re-check and forward?" n; then
            run_remedy disk "$target" || true
        else
            echo -e "${YELLOW}Command cancelled${NC}"
        fi
    fi
}

tools_menu() {
    local -a themes=()
    local line theme args
    while IFS= read -r line; do
        [ -n "$line" ] && themes+=("$line")
    done < <(jack_themes)
    if theme=$(pick_or_cancel "Select a jack theme" "${themes[@]}"); then
        args=$(tuin_input "Arguments for jack $theme (empty lists actions)")
        confirm_and_run "jack $theme $args"
    fi
}
```

The `${RED}`, `${CYAN}`, `${NC}` and `${YELLOW}` variables come from `lib/colors.sh`, which `cli.sh` sources before this module.

**Step 4: Wire it into `bin/cli.sh`**

Add after `source "$SCRIPT_DIR/cli/update.sh"`:

```bash
source "$SCRIPT_DIR/cli/tools.sh"
```

Replace the main menu block in `main_menu_loop`:

```bash
        local -a items=(
            "Install / Setup" "Health" "Pipeline" "Intelligence"
            "Notifications" "Cluster" "Updates"
        )
        jack_enabled && items+=("Tools")
        if tuin_menu "Select an option" "${items[@]}"
        then
            case $TUIN_REPLY in
                ...
                "Updates")         update_menu ;;
                "Tools")           tools_menu ;;
            esac
```

**Step 5: Add the disk item to `bin/cli/health.sh`**

Replace the fixed `tuin_menu "Health" ...` argument list with an array:

```bash
        local -a items=(
            "Run all health checks"
            "Run specific checkers"
            "Run a single checker"
            "List available checkers"
            "Preflight dashboard"
            "JSON output (all checks)"
            "CI mode: fail on warning"
            "CI mode: fail on critical only"
        )
        jack_enabled && items+=("Disk cleanup (jack)")
        if tuin_menu "Health" "${items[@]}"
        then
```

and add a branch before `esac || true`:

```bash
                "Disk cleanup (jack)")
                    disk_remedy_menu ;;
```

**Step 6: Run the CLI suites**

Run: `./bin/tests/test_helper/bats-core/bin/bats bin/tests/lib/ bin/tests/`
Expected: all pass, including `test_cli.bats` and `test_cli_seteov.bats`.

**Step 7: Commit**

```bash
git add bin/cli/tools.sh bin/cli.sh bin/cli/health.sh bin/tests/test_tools.bats
git commit -m "feat(cli): add jack Tools menu and disk remedy flow"
```

---

### Task 8: Docs and verification

**Files:**
- Modify: `bin/README.md` (new `Jack (optional)` section after `cli.sh`)
- Modify: `apps/alerts/README.md` (`record_remedy` entry)
- Modify: `README.md` (one line in the documentation map)

**Step 1: Document**

`bin/README.md` section, in prose: what the opt-in is, where the state file lives, the three values, `install.sh jack`, that `--yes` installs jack, that non-interactive runs without `--yes` skip and stay unset, the Tools menu, and the four-step disk cleanup flow.

`apps/alerts/README.md`: the `record_remedy` flag table from the design doc and the JSON example.

**Step 2: Format and lint**

Run: `uv run black . && uv run ruff check . --fix`
Expected: no errors. Commit any formatting changes separately.

**Step 3: Full verification**

Run: `uv run pytest -q`
Expected: all pass.

Run: `./bin/tests/test_helper/bats-core/bin/bats bin/tests/lib/ bin/tests/`
Expected: all pass.

**Step 4: Manual check of the interactive paths**

bats cannot cover these, so run them by hand with a scratch config dir:

1. `JACK_STATE_FILE=/tmp/jack-state ./bin/install.sh jack` in a terminal. Answer `n`. Expect `/tmp/jack-state` to contain `off`, and a second run to print nothing.
2. Delete the file, run again, answer `y`. Expect jack cloned, linked, state `on`.
3. `./bin/cli.sh`. Expect a `Tools` entry and, under Health, `Disk cleanup (jack)`.
4. With a firing disk alert, run the disk cleanup. Expect the timeline row, the alert cleared by the re-check, and the push output.
5. `JACK_STATE_FILE=/tmp/jack-state-2 ./bin/install.sh --yes jack`. Flags go before the step. Expect no prompt, jack installed and state `on`.

**Step 5: Commit**

```bash
git add bin/README.md apps/alerts/README.md README.md
git commit -m "docs: document the jack opt-in and record_remedy"
```

---

## Order and dependencies

Task 1 is independent of the rest, but Task 5 tests assume `jack --version` prints `jack <version>`. Tasks 2 to 4 are sequential. Tasks 5 to 7 are sequential and independent of 2 to 4 until the manual check in Task 8. Task 0 comes first for everything in server-monitoring.
