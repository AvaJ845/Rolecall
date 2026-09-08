"""Load and validate engine/companies.json — the registry that is the product's moat.

A missing `slug` used to KeyError mid-ingest; a bad `ats` used to fail deep in an
adapter. `load_companies()` now validates every entry up front and raises
`RegistryError` naming the offending entry, before any feed is touched.
"""
from __future__ import annotations

import json

from .ats import ADAPTERS
from ._util import ROOT

COMPANIES_PATH = ROOT / "engine" / "companies.json"

_REQUIRED = ("id", "name", "ats", "slug")


class RegistryError(ValueError):
    """companies.json is malformed. The message names the offending entry."""


def validate(companies) -> list:
    if not isinstance(companies, list) or not companies:
        raise RegistryError("companies.json has no non-empty 'companies' array")
    seen_ids = set()
    for i, c in enumerate(companies):
        where = "entry {}".format(i)
        if not isinstance(c, dict):
            raise RegistryError("{}: not an object: {!r}".format(where, c))
        where = "entry {} (id={!r})".format(i, c.get("id", "?"))
        missing = [k for k in _REQUIRED if not c.get(k)]
        if missing:
            raise RegistryError("{}: missing/empty {}".format(where, ", ".join(missing)))
        if c["ats"] not in ADAPTERS:
            raise RegistryError("{}: unknown ats {!r} (known: {})".format(
                where, c["ats"], ", ".join(sorted(ADAPTERS))))
        if c["id"] in seen_ids:
            raise RegistryError("{}: duplicate id {!r}".format(where, c["id"]))
        seen_ids.add(c["id"])
    return companies


def load_companies():
    """Returns (vertical, companies). Raises RegistryError on a malformed registry."""
    try:
        data = json.loads(COMPANIES_PATH.read_text())
    except (OSError, ValueError) as e:
        raise RegistryError("cannot read {}: {}".format(COMPANIES_PATH, e))
    companies = validate(data.get("companies"))
    return data.get("vertical", ""), companies
