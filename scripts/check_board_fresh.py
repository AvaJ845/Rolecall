#!/usr/bin/env python3
"""Fail if a bundled board.json is stale (P0-18).

    python3 scripts/check_board_fresh.py [path-to-board.json] [--max-age-days N]

Defaults: ios/Rolecall/Resources/board.json, 3 days. Exit 0 if fresh, 1 if stale
or unreadable. Used as an Xcode archive build phase and by `make release-board`
so a release cut without re-running the engine can't ship a weeks-old
"verified live" board to every fresh install.
"""
from __future__ import annotations

import json
import pathlib
import sys
import time

DEFAULT_PATH = "ios/Rolecall/Resources/board.json"
DEFAULT_MAX_AGE_DAYS = 3.0


def main(argv) -> int:
    path = DEFAULT_PATH
    max_age_days = DEFAULT_MAX_AGE_DAYS
    it = iter(argv)
    for arg in it:
        if arg in ("--max-age-days", "-d"):
            max_age_days = float(next(it))
        elif arg in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            path = arg

    p = pathlib.Path(path)
    try:
        board = json.loads(p.read_text())
        generated = float(board["generated_utc"])
    except (OSError, ValueError, KeyError, TypeError) as e:
        print("::error::bundled board {} is unreadable or has no generated_utc: {}".format(p, e))
        return 1

    age_days = (time.time() - generated) / 86400.0
    if age_days > max_age_days:
        print("::error::bundled board {} is {:.1f} days old (limit {:.0f}). Refresh it: "
              "`make release-board`, then commit ios/Rolecall/Resources/board.json."
              .format(p, age_days, max_age_days))
        return 1
    if age_days < -1.0:
        print("::error::bundled board {} is dated {:.1f} days in the future — clock/skew bug?"
              .format(p, -age_days))
        return 1

    print("bundled board {} is {:.1f} days old ({} roles) — fresh (limit {:.0f}d).".format(
        p, max(age_days, 0.0), board.get("count", "?"), max_age_days))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
