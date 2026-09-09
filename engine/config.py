"""Declared board-generation config.

Flipping `INCLUDE_PM` here (a one-line config edit, not a source change buried in
classify.py) adds or removes every PM role from the board. `export()` stamps these
values into `board.json`'s `meta` block so a snapshot always records which ruleset
produced it — the signature covers `meta` automatically.

Bump `CLASSIFIER_VERSION` on *any* change to the `_DESIGN` / `_PM` / `_EXCLUDE` rules
or the `classify()` logic. The held-out family test reads it, and it lands in every
`board.json` so a snapshot's provenance is never ambiguous.
"""
from __future__ import annotations

# Include product-management roles in the "for designers" board.
INCLUDE_PM = True

# Bump on any edit to _DESIGN / _PM / _EXCLUDE or the classify() logic. Date-stamped
# so the ordering is obvious; the exact string is what lands in board.json.
CLASSIFIER_VERSION = "2026-09-08"

# The vertical this board covers. Mirrors companies.json "vertical".
VERTICAL = "product-design"


def meta(vertical: str = "") -> dict:
    """The `meta` object written into board.json."""
    return {
        "classifier_version": CLASSIFIER_VERSION,
        "include_pm": INCLUDE_PM,
        "vertical": vertical or VERTICAL,
    }
