"""Tiny stdlib-only HTTP helpers. No third-party deps by design (runs on system Python 3.9)."""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request

UA = (
    "RolecallEngine/0.1 (+https://rolecall.app; research spike; "
    "contact avaresearchLLC@gmail.com)"
)


def get_json(url: str, timeout: float = 20.0, retries: int = 2):
    """GET and parse JSON, with linear backoff. Raises RuntimeError on final failure."""
    last = None
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": UA, "Accept": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.loads(r.read().decode("utf-8"))
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError,
                json.JSONDecodeError, ConnectionError) as e:
            last = e
            if attempt < retries:
                time.sleep(1.5 * (attempt + 1))
    raise RuntimeError("GET failed {}: {}".format(url, last))


def check_url(url: str, timeout: float = 20.0):
    """
    GET a posting URL, following redirects.
    Returns (status_code, final_url, body_snippet_lowercased).
    status_code 0 means the request could not be completed at all.
    """
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read(65536).decode("utf-8", "ignore").lower()
            return r.getcode(), r.geturl(), body
    except urllib.error.HTTPError as e:
        return e.code, url, ""
    except Exception:
        return 0, url, ""
