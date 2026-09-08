"""Tiny stdlib-only HTTP helpers. No third-party deps by design (runs on system Python 3.9)."""
from __future__ import annotations

import json
import time
import urllib.error
import urllib.request

# Honest identifying UA for the public ATS JSON APIs — they don't bot-block and we want
# to be a good citizen / reachable if a provider has a question.
UA_API = (
    "RolecallEngine/0.1 (+https://rolecalljobs.com; research spike; "
    "contact avaresearchLLC@gmail.com)"
)

# Realistic browser UA for liveness checks only. Many corporate careers pages sit behind
# Cloudflare / Akamai and 403 a non-browser UA, which would otherwise look like a dead
# link and tank the audit accuracy number. We are only doing a GET to read the status of
# a page a company published publicly — no automation of an application flow.
UA_BROWSER = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)


def get_json(url: str, timeout: float = 20.0, retries: int = 2):
    """GET and parse JSON, with linear backoff. Raises RuntimeError on final failure."""
    last = None
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": UA_API, "Accept": "application/json"}
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
      status_code 0    -> the request could not be completed at all (DNS, timeout, TLS)
      status_code 403/429 -> reachable but bot-walled; caller should treat as ambiguous
    """
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": UA_BROWSER,
            "Accept": "text/html,application/xhtml+xml",
            "Accept-Language": "en-US,en;q=0.9",
        })
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read(65536).decode("utf-8", "ignore").lower()
            return r.getcode(), r.geturl(), body
    except urllib.error.HTTPError as e:
        return e.code, getattr(e, "url", url) or url, ""
    except Exception:
        return 0, url, ""
