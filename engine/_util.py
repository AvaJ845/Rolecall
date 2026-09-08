"""Tiny shared helpers for the engine command modules."""
from __future__ import annotations

import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"


def hms(secs: float) -> str:
    """Human-readable duration."""
    secs = int(secs)
    if secs < 90:
        return "{}s".format(secs)
    if secs < 5400:
        return "{}m".format(round(secs / 60))
    return "{:.1f}h".format(secs / 3600)
