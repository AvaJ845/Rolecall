"""Run: python -m engine.tests.test_release_checks

P0-18: scripts/check_board_fresh.py fails when the board bundled into the app is
older than the threshold, so a release cut without re-running the engine can't
ship a stale "verified live" board.
"""
from __future__ import annotations

import importlib.util
import json
import os
import pathlib
import tempfile
import time

_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
_spec = importlib.util.spec_from_file_location(
    "check_board_fresh", _ROOT / "scripts" / "check_board_fresh.py")
cbf = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cbf)

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def _board(age_days):
    d = tempfile.mkdtemp()
    p = pathlib.Path(d) / "board.json"
    p.write_text(json.dumps({
        "generated_utc": time.time() - age_days * 86400,
        "count": 3,
        "roles": [],
    }))
    return str(p)


@case
def test_fresh_board_passes():
    assert cbf.main([_board(1.0), "--max-age-days", "3"]) == 0


@case
def test_stale_board_fails():
    assert cbf.main([_board(5.0), "--max-age-days", "3"]) == 1


@case
def test_missing_or_malformed_fails():
    assert cbf.main(["/no/such/board.json"]) == 1
    d = tempfile.mkdtemp()
    bad = pathlib.Path(d) / "board.json"
    bad.write_text('{"count": 3}')  # no generated_utc
    assert cbf.main([str(bad)]) == 1


@case
def test_future_dated_board_fails():
    d = tempfile.mkdtemp()
    p = pathlib.Path(d) / "board.json"
    p.write_text(json.dumps({"generated_utc": time.time() + 5 * 86400, "count": 0, "roles": []}))
    assert cbf.main([str(p), "-d", "3"]) == 1


@case
def test_the_actual_bundled_board_is_readable():
    # Not a freshness assertion (that would turn CI red 3 days after any release —
    # the *archive* build phase is the real gate). Just: the committed board parses
    # and has a generated_utc, and we surface its age.
    bundled = _ROOT / "ios" / "Rolecall" / "Resources" / "board.json"
    if not bundled.exists():
        print("  (skip: {} not present)".format(bundled))
        return
    board = json.loads(bundled.read_text())
    age = (time.time() - float(board["generated_utc"])) / 86400.0
    print("  bundled board is {:.1f} days old ({} roles)".format(age, board.get("count")))
    if age > 3:
        print("  NOTE: bundled board would fail the archive freshness gate — "
              "run `make release-board` before the next release.")


def run():
    fails = 0
    for fn in CASES:
        try:
            fn()
        except AssertionError as e:
            fails += 1
            print("  FAIL {}: {}".format(fn.__name__, e))
        except Exception as e:  # noqa: BLE001
            fails += 1
            print("  ERROR {}: {!r}".format(fn.__name__, e))
    print("{}/{} release-check cases pass".format(len(CASES) - fails, len(CASES)))
    return 1 if fails else 0


if __name__ == "__main__":
    import sys
    sys.exit(run())
