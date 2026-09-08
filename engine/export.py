"""`export` — write data/board.json, the artifact the app consumes.

Guards, in order:
  * refuse if the last ingest run never finished (crashed / half-updated DB) — P0-14
  * drop any role whose URL is not https:// and log the count               — P0-13
  * refuse if the live count fell > 30% vs the board already on disk         — P0-6
"""
from __future__ import annotations

import json
import os
import pathlib
import urllib.parse as urllib_parse

from . import config, store
from ._util import DATA

BOARD_PATH = DATA / "board.json"

# See P0-6: a partial upstream failure (a feed 200s with an empty/half list) *does* mark
# the missing roles 'gone' and would otherwise ship a thin, validly signed board that
# silently replaces a healthy one on every device.
BOARD_SHRINK_LIMIT = 0.30


def _is_https(url: str) -> bool:
    try:
        return urllib_parse.urlsplit(url or "").scheme.lower() == "https"
    except ValueError:
        return False


def _prev_board_count(path=None):
    """Live-role count of the board currently on disk (the previous run's, restored from
    the CI cache), or None if there isn't a readable one."""
    try:
        prev = json.loads(pathlib.Path(path or BOARD_PATH).read_text())
        n = int(prev.get("count", len(prev.get("roles", []))))
        return n if n >= 0 else None
    except Exception:  # noqa: BLE001 - missing / unreadable / malformed -> no baseline
        return None


def _board_shrink_error(new_count, prev_count, limit=BOARD_SHRINK_LIMIT):
    """A human-readable reason to refuse the export, or None if the board is fine."""
    if not prev_count or prev_count <= 0:
        return None
    if new_count >= prev_count * (1.0 - limit):
        return None
    drop = 100.0 * (prev_count - new_count) / prev_count
    return (
        "live role count fell {:.1f}% ({} -> {}), past the {:.0f}% guard. Refusing to "
        "publish a thin board — a partial upstream failure would silently halve every "
        "user's board. If this shrink is real (registry pruned, vertical narrowed), "
        "re-run with ROLECALL_ALLOW_BOARD_SHRINK=1.".format(
            drop, prev_count, new_count, limit * 100)
    )


def _shrink_override_set():
    return os.environ.get("ROLECALL_ALLOW_BOARD_SHRINK", "").strip().lower() in (
        "1", "true", "yes", "on")


def export():
    conn = store.connect()
    if store.last_ingest_incomplete(conn):
        conn.close()
        msg = ("last ingest run never finished (no finished_utc) — the DB may be "
               "half-updated. Re-run `python3 -m engine ingest` before exporting.")
        print("::error::{}".format(msg))
        print("error: {}".format(msg))
        return 1
    rows = conn.execute(
        """SELECT company_name, title, department, location, remote, url, role_family,
                  first_seen_utc, last_verified_utc, http_status
           FROM postings WHERE status = 'live'
           ORDER BY first_seen_utc DESC"""
    ).fetchall()
    conn.close()

    kept = [r for r in rows if _is_https(r["url"])]
    dropped = len(rows) - len(kept)
    if dropped:
        print("::warning::dropped {} non-https URLs from the board".format(dropped))
        print("dropped {} non-https URLs".format(dropped))

    out = [{
        "company": r["company_name"],
        "title": r["title"],
        "family": r["role_family"],
        "location": r["location"],
        "remote": bool(r["remote"]) if r["remote"] is not None else None,
        "url": r["url"],
        "first_seen": r["first_seen_utc"],
        "last_verified": r["last_verified_utc"],
    } for r in kept]

    err = _board_shrink_error(len(out), _prev_board_count())
    if err:
        if _shrink_override_set():
            print("::warning::{} (allowed by ROLECALL_ALLOW_BOARD_SHRINK)".format(err))
        else:
            print("::error::{}".format(err))
            print("error: {}".format(err))
            return 1

    # P0-11: stamp the ruleset that produced this snapshot. The signature is over the
    # exact bytes, so `meta` is covered automatically; the app decodes it as optional.
    board = {
        "generated_utc": store.now(),
        "count": len(out),
        "meta": config.meta(),
        "roles": out,
    }
    BOARD_PATH.write_text(json.dumps(board, indent=2))
    print("wrote {} live roles (classifier {}) -> {}".format(
        len(out), config.CLASSIFIER_VERSION, BOARD_PATH))
    return 0
