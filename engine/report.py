"""`stats` — coverage / freshness / status snapshot.
`audit` — hand-check a random sample of 'live' postings; compute verified-live accuracy
(the number that gates the build). Interactive; not run in CI.
"""
from __future__ import annotations

import random

from . import store
from .registry import load_companies


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


def audit(sample: int = 25):
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
        print("      {}".format(p["url"]))  # interactive audit only — never runs in CI
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
