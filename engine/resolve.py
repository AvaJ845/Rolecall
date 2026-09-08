"""`resolve` — re-probe every registry slug against all four ATS vendors and report
drift. An entry whose declared `ats` returns nothing but another vendor has the feed
has migrated and the registry needs an edit.
"""
from __future__ import annotations

from .ats import resolve_ats
from .registry import load_companies


def resolve():
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
