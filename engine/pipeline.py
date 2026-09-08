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
import pathlib
import random
import sys
import time

from . import store
from .ats import fetch_company
from .classify import classify
from .net import check_url

ROOT = pathlib.Path(__file__).resolve().parent.parent
COMPANIES_PATH = ROOT / "engine" / "companies.json"
BOARD_PATH = ROOT / "data" / "board.json"

# A posting URL that redirects to one of these path shapes has almost certainly been
# pulled — the ATS bounces closed roles to the careers index.
_DEAD_REDIRECT_HINTS = ("/jobs", "/careers", "/job-board", "?redirect", "/postings")
_DEAD_BODY_HINTS = (
    "no longer accepting applications",
    "this job is no longer",
    "position has been filled",
    "job not found",
    "page not found",
    "the job you are looking for",
)


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

def verify(limit: int = 300, min_age_hours: float = 0.0):
    """Secondary signal: HTTP-check live postings and flag ones that no longer look live.
    The authoritative freshness signal is still ingest (feed presence); this catches
    'still in the feed but the page is dead' and measures link health."""
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

    checked = flagged = 0
    for p in rows:
        code, final_url, body = check_url(p["url"])
        flag = None
        if code in (404, 410):
            flag = "http_{}".format(code)
        elif code == 0:
            flag = "unreachable"
        elif final_url != p["url"] and any(h in final_url for h in _DEAD_REDIRECT_HINTS) \
                and final_url.rstrip("/").count("/") <= 4:
            flag = "redirect_to_index"
        elif any(h in body for h in _DEAD_BODY_HINTS):
            flag = "closed_body_text"
        conn.execute(
            "UPDATE postings SET last_verified_utc = ?, http_status = ?, verify_flag = ? WHERE key = ?",
            (store.now(), code, flag, p["key"]),
        )
        checked += 1
        if flag:
            flagged += 1
            print("  FLAG {:<28} {:<18} {}".format(p["company_name"][:28], flag, p["url"]))
        if checked % 25 == 0:
            conn.commit()
    conn.commit()
    store.finish_run(conn, run_id, "checked={} flagged={}".format(checked, flagged))
    print("\nverify done: {} checked, {} flagged ({:.1f}%)".format(
        checked, flagged, (100.0 * flagged / checked) if checked else 0.0))
    conn.close()
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
    BOARD_PATH.write_text(json.dumps(
        {"generated_utc": store.now(), "count": len(out), "roles": out}, indent=2))
    print("wrote {} live roles -> {}".format(len(out), BOARD_PATH))
    conn.close()
    return 0
