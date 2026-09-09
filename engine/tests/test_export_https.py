"""Run: python -m engine.tests.test_export_https

`export()` drops any live posting whose URL is not https:// before it writes
(and signs) board.json, and logs the dropped count. The client-side
`Board.sanitized()` guard stays as defence in depth; this closes the hole for every
other consumer (web/ job pages, a future Android client).
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


@case
def test_is_https_predicate():
    assert export._is_https("https://boards.greenhouse.io/x/jobs/1")
    assert not export._is_https("http://boards.greenhouse.io/x/jobs/1")
    assert not export._is_https("javascript:alert(1)")
    assert not export._is_https("ftp://x/y")
    assert not export._is_https("")
    assert not export._is_https("//protocol-relative/x")


def _seed(db_path, urls):
    saved = store.DB_PATH
    store.DB_PATH = pathlib.Path(db_path)
    try:
        conn = store.connect()
        for i, u in enumerate(urls):
            c = {"id": "co{}".format(i % 5), "ats": "greenhouse",
                 "name": "Company {}".format(i % 5)}
            row = {"external_id": "req-{}".format(i), "title": "Product Designer {}".format(i),
                   "department": "Design", "location": "Remote", "remote": 1, "url": u}
            store.upsert_posting(conn, c, row, "design", "test")
        conn.commit()
        conn.close()
    finally:
        store.DB_PATH = saved


def _run_export(db_path, board_path):
    saved_db, saved_board = store.DB_PATH, export.BOARD_PATH
    store.DB_PATH = pathlib.Path(db_path)
    export.BOARD_PATH = pathlib.Path(board_path)
    try:
        return export.export()
    finally:
        store.DB_PATH, export.BOARD_PATH = saved_db, saved_board


@case
def test_non_https_rows_never_reach_board_json():
    with tempfile.TemporaryDirectory() as d:
        db = os.path.join(d, "rc.db")
        board = os.path.join(d, "board.json")
        urls = (
            ["https://boards.greenhouse.io/acme/jobs/{}".format(i) for i in range(8)]
            + ["http://insecure.example/apply", "javascript:alert(1)"]
        )
        _seed(db, urls)
        rc = _run_export(db, board)
        assert rc == 0
        written = json.loads(pathlib.Path(board).read_text())
        assert written["count"] == 8, written["count"]
        assert all(r["url"].startswith("https://") for r in written["roles"])


@case
def test_all_https_is_unchanged():
    with tempfile.TemporaryDirectory() as d:
        db = os.path.join(d, "rc.db")
        board = os.path.join(d, "board.json")
        _seed(db, ["https://x.example/jobs/{}".format(i) for i in range(6)])
        rc = _run_export(db, board)
        assert rc == 0
        assert json.loads(pathlib.Path(board).read_text())["count"] == 6


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
    print("{}/{} export-https cases pass".format(len(CASES) - fails, len(CASES)))
    return 1 if fails else 0


if __name__ == "__main__":
    import sys
    sys.exit(run())
