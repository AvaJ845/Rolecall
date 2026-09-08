"""
ATS adapters. Each returns a list of normalised posting dicts:

    {
      "external_id": str,     # stable id within that ATS board
      "title": str,
      "url": str,             # the company's own application page
      "location": str,
      "department": str,
      "remote": bool | None,
      "posted_at": str,       # ISO-ish, best effort
    }

All four endpoints below are PUBLIC and UNAUTHENTICATED — they return exactly what the
company chose to publish on its own careers page. No API key, no scraping of LinkedIn /
Indeed, no ToS grey area.
"""
from __future__ import annotations

from .net import get_json


def _norm(external_id, title, url, location="", department="", remote=None, posted_at=""):
    return {
        "external_id": str(external_id),
        "title": (title or "").strip(),
        "url": (url or "").strip(),
        "location": (location or "").strip(),
        "department": (department or "").strip(),
        "remote": remote,
        "posted_at": str(posted_at or ""),
    }


def _dedupe(rows):
    seen, out = set(), []
    for r in rows:
        if r["external_id"] in seen:
            continue
        seen.add(r["external_id"])
        out.append(r)
    return out


# --- Greenhouse -------------------------------------------------------------
# https://boards-api.greenhouse.io/v1/boards/{slug}/departments

def from_greenhouse(slug: str):
    data = get_json(
        "https://boards-api.greenhouse.io/v1/boards/{}/departments".format(slug)
    )
    rows = []

    def walk(dept):
        dname = dept.get("name", "") or ""
        for j in dept.get("jobs", []) or []:
            rows.append(_norm(
                external_id=j.get("id"),
                title=j.get("title", ""),
                url=j.get("absolute_url", ""),
                location=(j.get("location") or {}).get("name", ""),
                department=dname,
                remote=None,
                posted_at=j.get("updated_at", ""),
            ))
        for child in dept.get("children", []) or []:
            walk(child)

    for dept in data.get("departments", []) or []:
        walk(dept)
    return _dedupe(rows)


# --- Ashby ----------------------------------------------------------------
# https://api.ashbyhq.com/posting-api/job-board/{slug}

def from_ashby(slug: str):
    data = get_json(
        "https://api.ashbyhq.com/posting-api/job-board/{}".format(slug)
    )
    rows = []
    for j in data.get("jobs", []) or []:
        if j.get("isListed") is False:
            continue
        rows.append(_norm(
            external_id=j.get("id"),
            title=j.get("title", ""),
            url=j.get("jobUrl") or j.get("applyUrl") or "",
            location=j.get("location", "") or "",
            department=j.get("department", "") or j.get("team", "") or "",
            remote=bool(j.get("isRemote")),
            posted_at=j.get("publishedAt", "") or "",
        ))
    return _dedupe(rows)


# --- Lever --------------------------------------------------------------
# https://api.lever.co/v0/postings/{slug}?mode=json

def from_lever(slug: str):
    data = get_json(
        "https://api.lever.co/v0/postings/{}?mode=json".format(slug)
    )
    rows = []
    for j in data or []:
        cats = j.get("categories", {}) or {}
        loc = cats.get("location", "") or ""
        rows.append(_norm(
            external_id=j.get("id"),
            title=j.get("text", ""),
            url=j.get("hostedUrl") or j.get("applyUrl") or "",
            location=loc,
            department=cats.get("department", "") or cats.get("team", "") or "",
            remote=("remote" in loc.lower()),
            posted_at=j.get("createdAt", ""),
        ))
    return _dedupe(rows)


# --- Workable ---------------------------------------------------------
# https://apply.workable.com/api/v1/widget/accounts/{slug}?details=true

def from_workable(slug: str):
    data = get_json(
        "https://apply.workable.com/api/v1/widget/accounts/{}?details=true".format(slug)
    )
    rows = []
    for j in data.get("jobs", []) or []:
        loc = j.get("location", {}) or {}
        locstr = ", ".join(
            x for x in [loc.get("city", ""), loc.get("region", ""), loc.get("country", "")]
            if x
        )
        rows.append(_norm(
            external_id=j.get("shortcode") or j.get("id"),
            title=j.get("title", ""),
            url=j.get("url") or j.get("application_url") or "",
            location=locstr,
            department=j.get("department", "") or "",
            remote=bool(loc.get("telecommuting")),
            posted_at=j.get("published_on", "") or "",
        ))
    return _dedupe(rows)


ADAPTERS = {
    "greenhouse": from_greenhouse,
    "ashby": from_ashby,
    "lever": from_lever,
    "workable": from_workable,
}


def fetch_company(company: dict):
    """company is one entry from companies.json. Returns list of normalised rows."""
    ats = company["ats"]
    if ats not in ADAPTERS:
        raise ValueError("unknown ATS: {}".format(ats))
    return ADAPTERS[ats](company["slug"])
