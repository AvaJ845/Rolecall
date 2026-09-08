"""The Week-0 verification spike, as code.

Commands (see engine/__main__.py):
  doctor   validate every company slug resolves and returns roles
  ingest   pull all company feeds -> classify -> upsert; mark vanished roles 'gone'
  verify   HTTP-check live postings; flag ones whose URL no longer looks live
  audit    hand-check a random sample; compute verified-live accuracy
  stats    coverage / freshness / status snapshot
  export   write data/board.json (what the app would consume)
"""
from __future__ import annotations

import json
import os
import pathlib
import random
import re
import sys
import time
import urllib.parse as urllib_parse

from . import store
from .ats import fetch_company, resolve_ats
from .classify import classify
from .net import check_url

ROOT = pathlib.Path(__file__).resolve().parent.parent
COMPANIES_PATH = ROOT / "engine" / "companies.json"
BOARD_PATH = ROOT / "data" / "board.json"

# A posting URL that redirects to a careers-index path shape has probably been pulled —
# the ATS bounces closed roles to the index. BUT only treat it as dead if the
# destination carries no job-identifying token (some companies, e.g. Stripe, legitimately
# render a live posting at `/jobs/search?gh_jid=NNNN`).
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

# Tokens that mean "this URL still points at a specific requisition", not an index page.
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


def load_companies():
    data = json.loads(COMPANIES_PATH.read_text())
    return data["vertical"], data["companies"]


def _hms(secs: float) -> str:
    secs = int(secs)
    if secs < 90:
        return "{}s".format(secs)
    if secs < 5400:
        return "{}m".format(round(secs / 60))
    return "{:.1f}h".format(secs / 3600)


# --- doctor --------------------------------------------------------------

def doctor():
    _, companies = load_companies()
    print("checking {} companies...\n".format(len(companies)))
    ok = 0
    for c in companies:
        try:
            rows = fetch_company(c)
            hits = sum(1 for r in rows if classify(r["title"], r["department"])[0])
            print("  OK   {:<16} {:<10} {:>4} roles, {:>3} in-vertical".format(
                c["id"], c["ats"], len(rows), hits))
            ok += 1
        except Exception as e:  # noqa: BLE001 - spike; we want the reason printed
            print("  FAIL {:<16} {:<10} {}".format(c["id"], c["ats"], e))
    print("\n{}/{} company feeds resolved".format(ok, len(companies)))
    return 0 if ok == len(companies) else 1


# --- ingest -------------------------------------------------------------

def ingest():
    _, companies = load_companies()
    conn = store.connect()
    run_id = store.start_run(conn, "ingest")
    t0 = time.time()
    tot_new = tot_seen = tot_gone = tot_roles = 0
    failed = []

    for c in companies:
        try:
            rows = fetch_company(c)
        except Exception as e:  # noqa: BLE001
            failed.append((c["id"], str(e)))
            print("  ! {:<16} feed error: {}".format(c["id"], e))
            continue

        seen_keys = set()
        c_new = c_seen = 0
        for r in rows:
            is_target, fam, reason = classify(r["title"], r["department"])
            if not is_target:
                continue
            tot_roles += 1
            key = "{}|{}|{}".format(c["id"], c["ats"], r["external_id"])
            seen_keys.add(key)
            outcome = store.upsert_posting(conn, c, r, fam, reason)
            if outcome == "new":
                c_new += 1
            else:
                c_seen += 1
        gone = store.mark_gone_for_company(conn, c["id"], seen_keys)
        conn.commit()
        tot_new += c_new
        tot_seen += c_seen
        tot_gone += gone
        print("  {:<16} +{:<3} ~{:<3} -{:<3}".format(c["id"], c_new, c_seen, gone))

    store.finish_run(
        conn, run_id,
        "new={} seen={} gone={} failed={}".format(tot_new, tot_seen, tot_gone, len(failed)),
    )
    print("\ningest done in {}".format(_hms(time.time() - t0)))
    print("  in-vertical roles this run : {}".format(tot_roles))
    print("  new / seen / gone          : {} / {} / {}".format(tot_new, tot_seen, tot_gone))
    if failed:
        print("  feeds failed               : {}".format(", ".join(f[0] for f in failed)))
    conn.close()
    return 0


# --- verify -------------------------------------------------------------

def _short_url(url: str) -> str:
    """Company-careers host + a truncated path, no query string. Used in CI logs so the
    6-hourly build history is not a timestamped 'who is hiring designers' record (P0-16).
    The full URL is in the DB; pass --verbose to print it for local debugging."""
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
    """Secondary signal: HTTP-check live postings and flag ones that no longer look live.
    The authoritative freshness signal is still ingest (feed presence); this catches
    'still in the feed but the page is dead' and measures link health.

    `verbose` (local `--verbose` only; CI never passes it) prints the full posting URL
    for each flagged row. By default only the host + a truncated path is logged (P0-16)."""
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


# --- resolve ----------------------------------------------------------

def resolve():
    """Re-probe every registry slug against all four ATS vendors and report drift:
    an entry whose declared `ats` returns nothing but another vendor has the feed has
    migrated and the registry needs an edit."""
    _, companies = load_companies()
    print("re-resolving {} companies...\n".format(len(companies)))
    drift = []
    dead = []
    for c in companies:
        found = resolve_ats(c["slug"])
        if not found:
            dead.append(c["id"])
            print("  DEAD   {:<16} {:<10} no vendor returns a feed for '{}'".format(
                c["id"], c["ats"], c["slug"]))
        elif c["ats"] not in found:
            best = max(found, key=found.get)
            drift.append((c["id"], c["ats"], best))
            print("  MOVED  {:<16} {} -> {}   {}".format(c["id"], c["ats"], best, found))
        # else: declared ats is present -> fine
    print("\n{} ok, {} moved, {} dead".format(
        len(companies) - len(drift) - len(dead), len(drift), len(dead)))
    if drift:
        print("edit companies.json:  " + "; ".join(
            "{} -> {}".format(i, b) for i, _, b in drift))
    return 0


# --- audit --------------------------------------------------------------

def audit(sample: int = 25):
    """Hand-check: for a random sample of postings the engine calls 'live', ask a human
    whether the role is genuinely open. Produces the accuracy number that gates the build."""
    conn = store.connect()
    live = conn.execute("SELECT * FROM postings WHERE status = 'live'").fetchall()
    if not live:
        print("no live postings — run `ingest` first")
        return 1
    picks = random.sample(list(live), min(sample, len(live)))
    print("Hand-check {} of {} live postings. "
          "[o]pen  [c]losed/dead  [s]kip  [q]uit\n".format(len(picks), len(live)))
    confirmed = wrong = skipped = 0
    for i, p in enumerate(picks, 1):
        print("{:>2}/{}  {} — {}".format(i, len(picks), p["company_name"], p["title"]))
        print("      {}".format(p["url"]))
        ans = ""
        while ans not in ("o", "c", "s", "q"):
            ans = input("      open / closed / skip / quit ? ").strip().lower()[:1]
        verdict = {"o": "open", "c": "closed", "s": "skip", "q": "quit"}[ans]
        if ans != "s":
            conn.execute(
                "INSERT INTO audit_log (ts, posting_key, machine_status, human_verdict, url) "
                "VALUES (?,?,?,?,?)",
                (store.now(), p["key"], "live", verdict, p["url"]),
            )
            conn.commit()
        if ans == "o":
            confirmed += 1
        elif ans == "c":
            wrong += 1
        elif ans == "s":
            skipped += 1
        else:
            break
        print()

    judged = confirmed + wrong
    print("-" * 52)
    print("confirmed open : {}".format(confirmed))
    print("actually closed: {}".format(wrong))
    print("skipped        : {}".format(skipped))
    if judged:
        acc = 100.0 * confirmed / judged
        print("\nverified-live accuracy: {:.1f}%   (gate: >= 98.0%)".format(acc))
        print("VERDICT:", "PASS — engine is trustworthy" if acc >= 98.0
              else "FAIL — do not build the app yet")
    conn.close()
    return 0


# --- stats --------------------------------------------------------------

def stats():
    _, companies = load_companies()
    conn = store.connect()
    q = conn.execute
    live = q("SELECT COUNT(*) FROM postings WHERE status = 'live'").fetchone()[0]
    gone = q("SELECT COUNT(*) FROM postings WHERE status = 'gone'").fetchone()[0]
    total = live + gone
    print("companies seeded        : {}".format(len(companies)))
    print("postings tracked        : {}  (live {}, gone {})".format(total, live, gone))

    print("\nby role family (live):")
    for r in q("""SELECT COALESCE(role_family,'?') f, COUNT(*) n FROM postings
                  WHERE status='live' GROUP BY f ORDER BY n DESC"""):
        print("  {:<12} {}".format(r["f"], r["n"]))

    print("\nby company (live):")
    for r in q("""SELECT company_name, COUNT(*) n FROM postings
                  WHERE status='live' GROUP BY company_name ORDER BY n DESC"""):
        print("  {:<22} {}".format(r["company_name"], r["n"]))

    print("\nfreshness (live, time since first seen):")
    buckets = [("< 24h", 0, 86400), ("1-7d", 86400, 604800),
               ("7-30d", 604800, 2592000), ("> 30d", 2592000, 1e12)]
    nowt = store.now()
    for label, lo, hi in buckets:
        n = q("""SELECT COUNT(*) FROM postings WHERE status='live'
                 AND (?-first_seen_utc) >= ? AND (?-first_seen_utc) < ?""",
              (nowt, lo, nowt, hi)).fetchone()[0]
        print("  {:<8} {}".format(label, n))

    vflag = q("SELECT COUNT(*) FROM postings WHERE status='live' AND verify_flag IS NOT NULL").fetchone()[0]
    vdone = q("SELECT COUNT(*) FROM postings WHERE status='live' AND last_verified_utc IS NOT NULL").fetchone()[0]
    print("\nURL health (live): {} verified, {} flagged".format(vdone, vflag))

    aud = q("""SELECT human_verdict, COUNT(*) n FROM audit_log
               WHERE human_verdict IN ('open','closed') GROUP BY human_verdict""").fetchall()
    if aud:
        d = {r["human_verdict"]: r["n"] for r in aud}
        j = d.get("open", 0) + d.get("closed", 0)
        print("audit history    : {}/{} confirmed open ({:.1f}%)".format(
            d.get("open", 0), j, 100.0 * d.get("open", 0) / j if j else 0.0))
    conn.close()
    return 0


# --- export -----------------------------------------------------------

# Refuse to publish a board whose live count fell more than this fraction versus the
# last board we wrote. A bad upstream morning where a chunk of ATS feeds return a valid
# but partial/empty payload (which *does* mark the missing roles 'gone' — unlike a feed
# error, which is `continue`d and keeps its rows) would otherwise ship a thin, validly
# signed board that silently replaces a healthy one on every user's device. See P0-6.
BOARD_SHRINK_LIMIT = 0.30


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
    rows = conn.execute(
        """SELECT company_name, title, department, location, remote, url, role_family,
                  first_seen_utc, last_verified_utc, http_status
           FROM postings WHERE status = 'live'
           ORDER BY first_seen_utc DESC"""
    ).fetchall()
    out = [{
        "company": r["company_name"],
        "title": r["title"],
        "family": r["role_family"],
        "location": r["location"],
        "remote": bool(r["remote"]) if r["remote"] is not None else None,
        "url": r["url"],
        "first_seen": r["first_seen_utc"],
        "last_verified": r["last_verified_utc"],
    } for r in rows]
    conn.close()

    err = _board_shrink_error(len(out), _prev_board_count())
    if err:
        if _shrink_override_set():
            print("::warning::{} (allowed by ROLECALL_ALLOW_BOARD_SHRINK)".format(err))
        else:
            print("::error::{}".format(err))
            print("error: {}".format(err))
            return 1

    BOARD_PATH.write_text(json.dumps(
        {"generated_utc": store.now(), "count": len(out), "roles": out}, indent=2))
    print("wrote {} live roles -> {}".format(len(out), BOARD_PATH))
    return 0
