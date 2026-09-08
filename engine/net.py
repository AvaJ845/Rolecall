"""Tiny stdlib-only HTTP helpers. No third-party deps by design (runs on system Python 3.9).

SSRF posture (P0-2): every outbound request goes through `_resolve_and_follow`, which
  * refuses any scheme other than http/https,
  * refuses loopback / RFC1918-private / link-local / ULA / multicast / `.local` hosts,
    resolving the name first so a public name pointing at 127.0.0.1 is still refused,
  * disables automatic redirects and follows them manually, re-validating every hop,
  * caps the redirect chain at MAX_REDIRECTS.
This matters because these URLs come straight from third-party ATS feeds and are fetched
from the CI job that (until P0-3) also holds the board signing key.
"""
from __future__ import annotations

import ipaddress
import json
import socket
import time
import urllib.error
import urllib.parse
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

_API_HEADERS = {"User-Agent": UA_API, "Accept": "application/json"}
_BROWSER_HEADERS = {
    "User-Agent": UA_BROWSER,
    "Accept": "text/html,application/xhtml+xml",
    "Accept-Language": "en-US,en;q=0.9",
}

_ALLOWED_SCHEMES = ("http", "https")
_REDIRECT_CODES = (301, 302, 303, 307, 308)
MAX_REDIRECTS = 5


class _NoRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Never auto-follow: returning None makes urllib raise the 3xx as an HTTPError, which
    we catch and re-validate before following by hand."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: N802
        return None


_OPENER = urllib.request.build_opener(_NoRedirectHandler)


def _ip_reason(ip):
    """Return a string reason if this address must not be fetched, else None."""
    if (ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_multicast
            or ip.is_reserved or ip.is_unspecified):
        return "non-public address {}".format(ip)
    mapped = getattr(ip, "ipv4_mapped", None)
    if mapped is not None:
        return _ip_reason(mapped)
    return None


def _validate_url(url: str):
    """Return a string reason the URL must not be fetched, or None if it is allowed."""
    parts = urllib.parse.urlsplit(url)
    scheme = (parts.scheme or "").lower()
    if scheme not in _ALLOWED_SCHEMES:
        return "scheme not allowed: {!r}".format(parts.scheme)
    try:
        host = parts.hostname
    except ValueError as e:
        return "bad host in URL: {}".format(e)
    if not host:
        return "no host in URL"
    h = host.lower().rstrip(".")
    if h == "localhost" or h.endswith(".localhost") or h.endswith(".local"):
        return "loopback/mDNS host: {}".format(host)

    # Literal IP in the URL — check it directly, no DNS.
    try:
        return _ip_reason(ipaddress.ip_address(h))
    except ValueError:
        pass

    # Hostname — resolve and reject if *any* answer is non-public.
    try:
        default_port = 443 if scheme == "https" else 80
        infos = socket.getaddrinfo(host, parts.port or default_port,
                                   proto=socket.IPPROTO_TCP)
    except socket.gaierror as e:
        return "cannot resolve host {}: {}".format(host, e)
    for info in infos:
        try:
            ip = ipaddress.ip_address(info[4][0])
        except ValueError:
            continue
        reason = _ip_reason(ip)
        if reason:
            return reason
    return None


def _resolve_and_follow(url: str, headers: dict, timeout: float, read_limit):
    """Validate + fetch + follow redirects by hand, re-validating each hop.

    Returns (status_code, final_url, body_bytes). status_code 0 means the request was
    refused pre-flight (bad scheme / non-public host), a redirect pointed somewhere
    refused, or the chain exceeded MAX_REDIRECTS — in every case nothing further was
    fetched. `read_limit` None reads the whole body; an int truncates.
    """
    current = url
    for _ in range(MAX_REDIRECTS + 1):
        reason = _validate_url(current)
        if reason:
            return 0, current, b""
        req = urllib.request.Request(current, headers=headers)
        try:
            with _OPENER.open(req, timeout=timeout) as r:
                body = r.read() if read_limit is None else r.read(read_limit)
                return r.getcode(), r.geturl(), body
        except urllib.error.HTTPError as e:
            if e.code in _REDIRECT_CODES:
                loc = e.headers.get("Location") if e.headers else None
                if not loc:
                    return e.code, current, b""
                current = urllib.parse.urljoin(current, loc)
                continue
            return e.code, getattr(e, "url", None) or current, b""
    return 0, current, b""  # too many redirects


def get_json(url: str, timeout: float = 20.0, retries: int = 2):
    """GET and parse JSON, with linear backoff. Raises RuntimeError on final failure."""
    reason = _validate_url(url)
    if reason:
        raise RuntimeError("refused {}: {}".format(url, reason))
    last = None
    for attempt in range(retries + 1):
        try:
            code, final_url, raw = _resolve_and_follow(url, _API_HEADERS, timeout, None)
            if code == 0:
                raise RuntimeError("blocked redirect or too many hops for {}".format(url))
            if not (200 <= code < 300):
                raise RuntimeError("HTTP {} for {}".format(code, final_url))
            return json.loads(raw.decode("utf-8"))
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError,
                json.JSONDecodeError, ConnectionError, RuntimeError) as e:
            last = e
            if attempt < retries:
                time.sleep(1.5 * (attempt + 1))
    raise RuntimeError("GET failed {}: {}".format(url, last))


def check_url(url: str, timeout: float = 20.0):
    """
    GET a posting URL, following redirects (manually, re-validating each hop).
    Returns (status_code, final_url, body_snippet_lowercased).
      status_code 0    -> could not be completed at all, OR refused pre-flight
                          (bad scheme, non-public host, redirect into a non-public host)
      status_code 403/429 -> reachable but bot-walled; caller should treat as ambiguous
    """
    try:
        code, final_url, body = _resolve_and_follow(url, _BROWSER_HEADERS, timeout, 65536)
        return code, final_url, body.decode("utf-8", "ignore").lower()
    except Exception:
        return 0, url, ""
