"""Run: python -m engine.tests.test_cli_smoke

After splitting pipeline.py into per-command modules, every `engine <cmd>`
still dispatches, and a malformed companies.json fails fast with a message naming
the entry (instead of a KeyError deep in ingest).
"""
from __future__ import annotations

import io
import json
import os
import pathlib
import tempfile
from contextlib import redirect_stdout

from engine import __main__ as cli
from engine import export, ingest, registry, report, resolve, store, verify

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


@case
def test_every_command_is_wired():
    for cmd in ("doctor", "resolve", "ingest", "verify", "audit", "stats",
                "export", "sign", "keygen"):
        # We are not running them here (network / secrets); just prove the dispatch
        # branch exists and does not fall through to "unknown command".
        src = pathlib.Path(cli.__file__).read_text()
        assert 'cmd == "{}"'.format(cmd) in src, cmd


@case
def test_unknown_command_returns_2():
    buf = io.StringIO()
    with redirect_stdout(buf):
        rc = cli.main(["frobnicate"])
    assert rc == 2
    assert "unknown command" in buf.getvalue()


@case
def test_malformed_registry_fails_fast_naming_the_entry():
    with tempfile.TemporaryDirectory() as d:
        bad = pathlib.Path(d) / "companies.json"
        bad.write_text(json.dumps({"vertical": "x", "companies": [
            {"id": "figma", "name": "Figma", "ats": "greenhouse", "slug": "figma"},
            {"id": "oops", "name": "Oops", "ats": "greenhouse"},  # missing slug
        ]}))
        saved = registry.COMPANIES_PATH
        registry.COMPANIES_PATH = bad
        try:
            buf = io.StringIO()
            with redirect_stdout(buf):
                rc = cli.main(["ingest"])
            assert rc == 2, rc
            out = buf.getvalue()
            assert "oops" in out and "slug" in out, out
        finally:
            registry.COMPANIES_PATH = saved


@case
def test_stats_and_export_run_against_a_temp_db():
    with tempfile.TemporaryDirectory() as d:
        saved_db, saved_board = store.DB_PATH, export.BOARD_PATH
        store.DB_PATH = pathlib.Path(d) / "rc.db"
        export.BOARD_PATH = pathlib.Path(d) / "board.json"
        try:
            conn = store.connect()
            c = {"id": "figma", "ats": "greenhouse", "name": "Figma"}
            for i in range(3):
                store.upsert_posting(conn, c, {
                    "external_id": "r{}".format(i), "title": "Product Designer",
                    "department": "Design", "location": "Remote", "remote": 1,
                    "url": "https://boards.greenhouse.io/figma/jobs/{}".format(i)}, "design", "t")
            rid = store.start_run(conn, "ingest")
            store.finish_run(conn, rid, "ok")
            conn.close()

            buf = io.StringIO()
            with redirect_stdout(buf):
                assert cli.main(["stats"]) == 0
                assert cli.main(["export"]) == 0
            assert json.loads(export.BOARD_PATH.read_text())["count"] == 3
        finally:
            store.DB_PATH, export.BOARD_PATH = saved_db, saved_board


@case
def test_modules_are_small():
    # The Judge's "no module over ~150 lines" for the ex-god-module split.
    import engine
    root = pathlib.Path(engine.__file__).parent
    for name in ("ingest", "verify", "resolve", "report", "export", "registry", "__main__"):
        n = len((root / (name + ".py")).read_text().splitlines())
        assert n <= 155, "{}.py is {} lines".format(name, n)


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
    print("{}/{} cli-smoke cases pass".format(len(CASES) - fails, len(CASES)))
    return 1 if fails else 0


if __name__ == "__main__":
    import sys
    sys.exit(run())
