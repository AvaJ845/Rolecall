"""Run: python -m engine.tests.test_board_guard

The engine refuses to export a board whose live count fell >30% versus the
board already on disk (the previous run's, restored from the CI cache).
"""
from __future__ import annotations

import json
import os
import pathlib
import tempfile

from engine import export, store

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


# --- pure guard ------------------------------------------------------------

@case
def test_shrink_error_thresholds():
    assert export._board_shrink_error(300, 630) is not None      # 52% drop -> refuse
    assert export._board_shrink_error(440, 630) is not None      # 30.2% drop -> refuse
    assert export._board_shrink_error(441, 630) is None          # exactly 30% -> ok
    assert export._board_shrink_error(500, 630) is None          # 20% drop -> ok
    assert export._board_shrink_error(700, 630) is None          # grew -> ok


@case
def test_shrink_error_no_baseline():
    assert export._board_shrink_error(1, None) is None
    assert export._board_shrink_error(1, 0) is None


@case
def test_shrink_message_is_clear():
    msg = export._board_shrink_error(200, 630)
    assert "fell" in msg and "630 -> 200" in msg and "ROLECALL_ALLOW_BOARD_SHRINK" in msg


# --- export() integration -------------------------------------------------

def _seed_live_postings(db_path, n, company_ct=10):
    """Insert `n` live postings across `company_ct` companies into a fresh DB."""
    saved = store.DB_PATH
    store.DB_PATH = pathlib.Path(db_path)
    try:
        conn = store.connect()
        for i in range(n):
            c = {"id": "co{}".format(i % company_ct), "ats": "greenhouse",
                 "name": "Company {}".format(i % company_ct)}
            row = {"external_id": "req-{}".format(i), "title": "Product Designer {}".format(i),
                   "department": "Design", "location": "Remote", "remote": 1,
                   "url": "https://boards.greenhouse.io/co/jobs/{}".format(i)}
            store.upsert_posting(conn, c, row, "design", "test")
        conn.commit()
        conn.close()
    finally:
        store.DB_PATH = saved


def _run_export_with(db_path, board_path):
    saved_db, saved_board = store.DB_PATH, export.BOARD_PATH
    store.DB_PATH = pathlib.Path(db_path)
    export.BOARD_PATH = pathlib.Path(board_path)
    try:
        return export.export()
    finally:
        store.DB_PATH, export.BOARD_PATH = saved_db, saved_board


@case
def test_export_refuses_when_board_halved():
    with tempfile.TemporaryDirectory() as d:
        db = os.path.join(d, "rc.db")
        board = os.path.join(d, "board.json")
        # Previous board: 400 roles. This run: only 150 survived (a partial-feed morning).
        pathlib.Path(board).write_text(json.dumps({"generated_utc": 1.0, "count": 400, "roles": []}))
        _seed_live_postings(db, 150)

        rc = _run_export_with(db, board)
        assert rc == 1, "export must fail non-zero on a >30% shrink"
        # The old board on disk is untouched.
        assert json.loads(pathlib.Path(board).read_text())["count"] == 400


@case
def test_export_allows_shrink_with_override():
    with tempfile.TemporaryDirectory() as d:
        db = os.path.join(d, "rc.db")
        board = os.path.join(d, "board.json")
        pathlib.Path(board).write_text(json.dumps({"generated_utc": 1.0, "count": 400, "roles": []}))
        _seed_live_postings(db, 150)

        os.environ["ROLECALL_ALLOW_BOARD_SHRINK"] = "1"
        try:
            rc = _run_export_with(db, board)
        finally:
            del os.environ["ROLECALL_ALLOW_BOARD_SHRINK"]
        assert rc == 0
        assert json.loads(pathlib.Path(board).read_text())["count"] == 150


@case
def test_export_writes_normally_on_a_healthy_run():
    with tempfile.TemporaryDirectory() as d:
        db = os.path.join(d, "rc.db")
        board = os.path.join(d, "board.json")
        pathlib.Path(board).write_text(json.dumps({"generated_utc": 1.0, "count": 400, "roles": []}))
        _seed_live_postings(db, 380)   # 5% drop

        rc = _run_export_with(db, board)
        assert rc == 0
        written = json.loads(pathlib.Path(board).read_text())
        assert written["count"] == 380 and len(written["roles"]) == 380


@case
def test_export_writes_when_no_prior_board():
    with tempfile.TemporaryDirectory() as d:
        db = os.path.join(d, "rc.db")
        board = os.path.join(d, "board.json")   # does not exist
        _seed_live_postings(db, 5)
        rc = _run_export_with(db, board)
        assert rc == 0
        assert json.loads(pathlib.Path(board).read_text())["count"] == 5


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
    print("{}/{} board-guard cases pass".format(len(CASES) - fails, len(CASES)))
    return 1 if fails else 0


if __name__ == "__main__":
    import sys
    sys.exit(run())
