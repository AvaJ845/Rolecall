"""Run: python -m engine.tests.test_config_meta

INCLUDE_PM (and the classifier version + vertical) are declared in
engine/config.py, and export() stamps them into board.json's `meta` block so a
snapshot records which ruleset produced it.
"""
from __future__ import annotations

import json
import os
import pathlib
import tempfile

from engine import classify as classify_mod
from engine import config, export, store
from engine.classify import classify

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


@case
def test_meta_shape():
    m = config.meta()
    assert set(m) == {"classifier_version", "include_pm", "vertical"}
    assert isinstance(m["include_pm"], bool)
    assert m["classifier_version"] == config.CLASSIFIER_VERSION
    assert m["vertical"] == config.VERTICAL


@case
def test_classify_reads_config_include_pm_live():
    saved = config.INCLUDE_PM
    try:
        config.INCLUDE_PM = True
        assert classify("Group Product Manager")[0] is True
        config.INCLUDE_PM = False
        ok, fam, reason = classify("Group Product Manager")
        assert ok is False and "pm" in reason
        # a plain designer is unaffected by the PM toggle
        assert classify("Senior Product Designer", "Design")[0] is True
    finally:
        config.INCLUDE_PM = saved


@case
def test_export_writes_meta_block():
    with tempfile.TemporaryDirectory() as d:
        saved_db, saved_board = store.DB_PATH, export.BOARD_PATH
        store.DB_PATH = pathlib.Path(d) / "rc.db"
        export.BOARD_PATH = pathlib.Path(d) / "board.json"
        try:
            conn = store.connect()
            c = {"id": "figma", "ats": "greenhouse", "name": "Figma"}
            for i in range(4):
                store.upsert_posting(conn, c, {
                    "external_id": "r{}".format(i), "title": "Product Designer",
                    "department": "Design", "location": "Remote", "remote": 1,
                    "url": "https://boards.greenhouse.io/figma/jobs/{}".format(i)}, "design", "t")
            rid = store.start_run(conn, "ingest")
            store.finish_run(conn, rid, "ok")
            conn.close()

            assert export.export() == 0
            board = json.loads(export.BOARD_PATH.read_text())
            assert board["meta"] == config.meta(), board.get("meta")
            assert board["meta"]["classifier_version"] == config.CLASSIFIER_VERSION
            # meta comes before roles so a human reading the file sees it first
            assert list(board.keys()).index("meta") < list(board.keys()).index("roles")
        finally:
            store.DB_PATH, export.BOARD_PATH = saved_db, saved_board


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
    print("{}/{} config-meta cases pass".format(len(CASES) - fails, len(CASES)))
    return 1 if fails else 0


if __name__ == "__main__":
    import sys
    sys.exit(run())
