"""Run: python -m engine.tests.test_sqlite_session

The engine's SQLite session is hardened (WAL + busy_timeout + foreign_keys +
synchronous=NORMAL), ingest is one transaction, and export refuses to publish off a
DB whose last ingest never finished.
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


def _fresh_db(d):
    saved = store.DB_PATH
    store.DB_PATH = pathlib.Path(os.path.join(d, "rc.db"))
    return saved


@case
def test_connect_sets_the_four_pragmas():
    with tempfile.TemporaryDirectory() as d:
        saved = _fresh_db(d)
        try:
            conn = store.connect()
            assert conn.execute("PRAGMA journal_mode").fetchone()[0].lower() == "wal"
            assert conn.execute("PRAGMA foreign_keys").fetchone()[0] == 1
            assert conn.execute("PRAGMA busy_timeout").fetchone()[0] == 5000
            assert conn.execute("PRAGMA synchronous").fetchone()[0] == 1  # NORMAL
            conn.close()
        finally:
            store.DB_PATH = saved


def _seed_live(conn, n):
    for i in range(n):
        c = {"id": "co{}".format(i % 4), "ats": "greenhouse", "name": "Co {}".format(i % 4)}
        row = {"external_id": "r{}".format(i), "title": "Product Designer {}".format(i),
               "department": "Design", "location": "Remote", "remote": 1,
               "url": "https://x.example/jobs/{}".format(i)}
        store.upsert_posting(conn, c, row, "design", "t")
    conn.commit()


def _export(d):
    saved_board = export.BOARD_PATH
    export.BOARD_PATH = pathlib.Path(os.path.join(d, "board.json"))
    try:
        return export.export(), export.BOARD_PATH
    finally:
        export.BOARD_PATH = saved_board


@case
def test_export_refuses_after_a_crashed_ingest():
    with tempfile.TemporaryDirectory() as d:
        saved = _fresh_db(d)
        try:
            conn = store.connect()
            _seed_live(conn, 10)
            # an ingest that started and never finished
            conn.execute("INSERT INTO runs (kind, started_utc) VALUES ('ingest', ?)",
                         (store.now(),))
            conn.commit()
            conn.close()

            rc, board = _export(d)
            assert rc == 1, "export must refuse after a crashed ingest"
            assert not board.exists(), "no board.json should be written"
        finally:
            store.DB_PATH = saved


@case
def test_export_runs_after_a_clean_ingest():
    with tempfile.TemporaryDirectory() as d:
        saved = _fresh_db(d)
        try:
            conn = store.connect()
            _seed_live(conn, 10)
            rid = store.start_run(conn, "ingest")
            store.finish_run(conn, rid, "ok")
            conn.close()

            rc, board = _export(d)
            assert rc == 0
            assert json.loads(board.read_text())["count"] == 10
        finally:
            store.DB_PATH = saved


@case
def test_last_ingest_incomplete_helper():
    with tempfile.TemporaryDirectory() as d:
        saved = _fresh_db(d)
        try:
            conn = store.connect()
            assert store.last_ingest_incomplete(conn) is False  # no runs at all
            rid = store.start_run(conn, "ingest")
            assert store.last_ingest_incomplete(conn) is True
            store.finish_run(conn, rid, "done")
            assert store.last_ingest_incomplete(conn) is False
            conn.close()
        finally:
            store.DB_PATH = saved


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
    print("{}/{} sqlite-session cases pass".format(len(CASES) - fails, len(CASES)))
    return 1 if fails else 0


if __name__ == "__main__":
    import sys
    sys.exit(run())
