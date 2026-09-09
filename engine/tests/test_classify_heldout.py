"""Run: python -m engine.tests.test_classify_heldout

A held-out labelled set (engine/tests/labelled_titles.jsonl) that measures
*which* roles the classifier over-blocks or leaks as the registry — the moat —
grows. Asserts family assignment for target rows and precision/recall against a
committed floor. The labels are our intended ground truth, not classify() output.

If a rule edit in engine/classify.py moves these numbers, bump
engine/config.CLASSIFIER_VERSION and re-review the labelled file.
"""
from __future__ import annotations

import json
import pathlib

from engine import config
from engine.classify import classify

LABELS_PATH = pathlib.Path(__file__).resolve().parent / "labelled_titles.jsonl"

# Committed floors. classifier 2026-09-08 scores P=1.00, R=1.00, family=1.00 on this
# set (the labels were assigned by rules close to classify()'s, so a clean pass is
# expected today). The floors leave room for a deliberate small improvement without a
# version bump, and fail loudly on a regression — which is the signal to bump
# config.CLASSIFIER_VERSION and re-review labelled_titles.jsonl.
PRECISION_FLOOR = 0.97
RECALL_FLOOR = 0.92
FAMILY_ACCURACY_FLOOR = 0.96
MIN_ROWS = 200
MIN_COMPANIES = 20

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def _load():
    rows = []
    for line in LABELS_PATH.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        rows.append(json.loads(line))
    return rows


@case
def test_labelled_set_is_big_and_broad():
    rows = _load()
    assert len(rows) >= MIN_ROWS, "only {} rows".format(len(rows))
    companies = {r["company"] for r in rows}
    assert len(companies) >= MIN_COMPANIES, "only {} companies".format(len(companies))
    targets = [r for r in rows if r["is_target"]]
    assert len(targets) >= 100
    fams = {r["family"] for r in targets}
    assert fams == {"design", "design-eng", "research", "pm"}, fams
    for r in rows:
        assert set(r) >= {"company", "title", "department", "is_target", "family"}
        if r["is_target"]:
            assert r["family"] in ("design", "design-eng", "research", "pm")
        else:
            assert r["family"] is None


@case
def test_family_assignment_for_target_rows():
    rows = _load()
    agreed = 0
    fam_ok = 0
    misses = []
    for r in rows:
        ok, fam, _ = classify(r["title"], r["department"])
        if r["is_target"] and ok:
            agreed += 1
            if fam == r["family"]:
                fam_ok += 1
            else:
                misses.append((r["title"], r["family"], fam))
    acc = fam_ok / agreed if agreed else 0.0
    if misses:
        print("  family mismatches ({:.3f} acc): {}".format(acc, misses[:8]))
    assert acc >= FAMILY_ACCURACY_FLOOR, "family accuracy {:.3f} < {}".format(
        acc, FAMILY_ACCURACY_FLOOR)


@case
def test_precision_and_recall_against_the_floor():
    rows = _load()
    tp = fp = fn = 0
    leaks, blocks = [], []
    for r in rows:
        ok, _, _ = classify(r["title"], r["department"])
        if r["is_target"] and ok:
            tp += 1
        elif r["is_target"] and not ok:
            fn += 1
            blocks.append(r["title"])
        elif not r["is_target"] and ok:
            fp += 1
            leaks.append(r["title"])
    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    print("  classifier {}: precision {:.3f}  recall {:.3f}  (tp={} fp={} fn={})".format(
        config.CLASSIFIER_VERSION, precision, recall, tp, fp, fn))
    if leaks:
        print("  leaked (want reject): {}".format(leaks[:6]))
    if blocks:
        print("  over-blocked (want match): {}".format(blocks[:6]))
    assert precision >= PRECISION_FLOOR, "precision {:.3f} < {}".format(precision, PRECISION_FLOOR)
    assert recall >= RECALL_FLOOR, "recall {:.3f} < {}".format(recall, RECALL_FLOOR)


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
    print("{}/{} classify-heldout cases pass".format(len(CASES) - fails, len(CASES)))
    return 1 if fails else 0


if __name__ == "__main__":
    import sys
    sys.exit(run())
