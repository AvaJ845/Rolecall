"""`ingest` — pull every company feed, classify, upsert; mark vanished roles 'gone'.
Also `doctor`, a read-only feed health check.

Feed fetches run in a bounded thread pool (the ATS APIs are independent hosts); all
DB writes stay single-threaded on this thread. A per-run wall-clock cap stops one
slow host from blowing the CI budget at registry scale.
"""
from __future__ import annotations

import concurrent.futures
import time

from . import store
from .ats import fetch_company
from .classify import classify
from .registry import load_companies
from ._util import hms

MAX_WORKERS = 8
WALL_CLOCK_S = 25 * 60  # a whole ingest run must finish inside this


def _fetch_all(companies):
    """Fetch every feed concurrently. Returns (results, failed) where results is a list
    of (company, rows) and failed is a list of (company_id, error_str). No DB access."""
    results, failed = [], []
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        futs = {ex.submit(fetch_company, c): c for c in companies}
        try:
            for fut in concurrent.futures.as_completed(futs, timeout=WALL_CLOCK_S):
                c = futs[fut]
                try:
                    results.append((c, fut.result()))
                except Exception as e:  # noqa: BLE001 - the reason is printed
                    failed.append((c["id"], str(e)))
        except concurrent.futures.TimeoutError:
            for fut, c in futs.items():
                if not fut.done():
                    failed.append((c["id"], "wall-clock cap ({}s) hit".format(WALL_CLOCK_S)))
            ex.shutdown(wait=False, cancel_futures=True)
    return results, failed


def doctor():
    _, companies = load_companies()
    print("checking {} companies...\n".format(len(companies)))
    results, failed = _fetch_all(companies)
    for c, rows in sorted(results, key=lambda cr: cr[0]["id"]):
        hits = sum(1 for r in rows if classify(r["title"], r["department"])[0])
        print("  OK   {:<16} {:<10} {:>4} roles, {:>3} in-vertical".format(
            c["id"], c["ats"], len(rows), hits))
    for cid, err in failed:
        print("  FAIL {:<16} {}".format(cid, err))
    print("\n{}/{} company feeds resolved".format(len(results), len(companies)))
    return 0 if not failed else 1


def ingest():
    _, companies = load_companies()
    conn = store.connect()
    run_id = store.start_run(conn, "ingest")
    t0 = time.time()

    results, failed = _fetch_all(companies)
    for cid, err in failed:
        print("  ! {:<16} feed error: {}".format(cid, err))

    tot_new = tot_seen = tot_gone = tot_roles = 0
    for c, rows in results:
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
        tot_new += c_new
        tot_seen += c_seen
        tot_gone += gone
        print("  {:<16} +{:<3} ~{:<3} -{:<3}".format(c["id"], c_new, c_seen, gone))

    # One transaction for the whole run: a crash before this line rolls back every upsert,
    # and the runs row (committed by start_run) still has no finished_utc, so export refuses.
    conn.commit()
    store.finish_run(
        conn, run_id,
        "new={} seen={} gone={} failed={}".format(tot_new, tot_seen, tot_gone, len(failed)),
    )
    print("\ningest done in {}".format(hms(time.time() - t0)))
    print("  in-vertical roles this run : {}".format(tot_roles))
    print("  new / seen / gone          : {} / {} / {}".format(tot_new, tot_seen, tot_gone))
    if failed:
        print("  feeds failed               : {}".format(", ".join(f[0] for f in failed)))
    conn.close()
    return 0
