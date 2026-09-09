"""`verify` — a secondary signal: HTTP-check live postings and flag ones that no
longer look live. The authoritative freshness signal is still ingest (feed presence);
this catches 'still in the feed but the page is dead' and measures link health.
"""
from __future__ import annotations

import re
import urllib.parse as urllib_parse

from . import store
from .net import check_url

# A posting URL that redirects to a careers-index path shape has probably been pulled —
# the ATS bounces closed roles to the index. BUT only treat it as dead if the destination
# carries no job-identifying token (Stripe renders a live posting at /jobs/search?gh_jid=N).
_DEAD_REDIRECT_HINTS = ("/jobs", "/careers", "/job-board", "?redirect", "/postings", "/openings")
_DEAD_BODY_HINTS = (
    "no longer accepting applications",
    "this job is no longer",
    "this position is no longer",
    "position has been filled",
    "job not found",
    "page not found",
    "the job you are looking for",
    "no longer available",
    "posting is closed",
)

_JOB_ID_RE = re.compile(
    r"(?:gh_jid|gh_jobid|gid|job[_-]?id|jobid|lever|ashby_jid|req[_-]?id)=[\w-]+"
    r"|/jobs?/\d{3,}"
    r"|/postings?/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}"
    r"|/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}"
    r"|/\d{5,}(?:[/?#]|$)",
    re.I,
)


def _has_job_identifier(url: str) -> bool:
    return bool(_JOB_ID_RE.search(url or ""))


def _looks_like_index(url: str) -> bool:
    """True if the URL path is shallow enough and hint-y enough to be a careers index."""
    path = re.sub(r"^https?://[^/]+", "", url or "")
    depth = path.strip("/").count("/")
    return depth <= 2 and any(h in url for h in _DEAD_REDIRECT_HINTS)


def _short_url(url: str) -> str:
    """Host + a truncated path, no query string. Used in CI logs so the 6-hourly build
    history is not a timestamped 'who is hiring designers' record. The full URL is in
    the DB; pass --verbose to print it for local debugging."""
    try:
        parts = urllib_parse.urlsplit(url or "")
    except ValueError:
        return "<unparseable url>"
    host = parts.netloc or "?"
    path = parts.path or "/"
    if len(path) > 16:
        path = path[:15] + "…"
    return "{}{}".format(host, path)


def verify(limit: int = 300, min_age_hours: float = 0.0, verbose: bool = False):
    """`verbose` (local `--verbose` only; CI never passes it) prints the full posting URL
    for each flagged row. By default only the host + a truncated path is logged."""
    conn = store.connect()
    run_id = store.start_run(conn, "verify")
    cutoff = store.now() - min_age_hours * 3600
    rows = conn.execute(
        """SELECT * FROM postings
           WHERE status = 'live' AND first_seen_utc <= ?
           ORDER BY last_verified_utc IS NOT NULL, last_verified_utc ASC
           LIMIT ?""",
        (cutoff, limit),
    ).fetchall()

    # "dead" flags mean the link is very likely broken; "ambiguous" flags mean we could
    # not tell (bot wall, transient network) and must NOT count against accuracy.
    dead_flags = {"http_404", "http_410", "redirect_to_index", "closed_body_text"}
    checked = dead = ambiguous = 0
    for p in rows:
        code, final_url, body = check_url(p["url"])
        flag = None
        if code in (404, 410):
            flag = "http_{}".format(code)
        elif code in (403, 429):
            flag = "bot_walled"          # ambiguous
        elif code == 0:
            flag = "unreachable"          # ambiguous
        elif (final_url != p["url"]
              and _looks_like_index(final_url)
              and not _has_job_identifier(final_url)):
            flag = "redirect_to_index"
        elif any(h in body for h in _DEAD_BODY_HINTS):
            flag = "closed_body_text"
        conn.execute(
            "UPDATE postings SET last_verified_utc = ?, http_status = ?, verify_flag = ? WHERE key = ?",
            (store.now(), code, flag, p["key"]),
        )
        checked += 1
        loc = p["url"] if verbose else _short_url(p["url"])
        if flag in dead_flags:
            dead += 1
            print("  DEAD  {:<26} {:<18} {}".format(p["company_name"][:26], flag, loc))
        elif flag:
            ambiguous += 1
            print("  ????  {:<26} {:<18} {}".format(p["company_name"][:26], flag, loc))
        if checked % 25 == 0:
            conn.commit()
    conn.commit()
    store.finish_run(
        conn, run_id, "checked={} dead={} ambiguous={}".format(checked, dead, ambiguous))
    print("\nverify done: {} checked".format(checked))
    print("  likely-dead links : {} ({:.2f}%)".format(
        dead, (100.0 * dead / checked) if checked else 0.0))
    print("  ambiguous (walls) : {} ({:.2f}%)".format(
        ambiguous, (100.0 * ambiguous / checked) if checked else 0.0))
    conn.close()
    return 0
