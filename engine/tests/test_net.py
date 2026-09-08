"""Run: python -m engine.tests.test_net

Covers P0-2: check_url / get_json scheme allowlist + SSRF host filtering, re-checked
across redirects. Fully offline — the redirect cases use a fake opener.
"""
from __future__ import annotations

import urllib.error

from engine import net


class _FakeResp:
    def __init__(self, code, url, body=b""):
        self._code, self._url, self._body = code, url, body

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def read(self, n=None):
        return self._body if n is None else self._body[:n]

    def getcode(self):
        return self._code

    def geturl(self):
        return self._url


class _FakeOpener:
    """Serves a scripted list of responses, one per hop. Each entry is either
    ('redirect', location) or ('ok', code, body_bytes)."""

    def __init__(self, script):
        self.script = list(script)
        self.calls = 0

    def open(self, req, timeout=None):
        self.calls += 1
        if not self.script:
            raise AssertionError("opener called more times than scripted")
        kind = self.script.pop(0)
        if kind[0] == "redirect":
            raise urllib.error.HTTPError(
                req.full_url, 302, "Found", {"Location": kind[1]}, None)
        return _FakeResp(kind[1], req.full_url, kind[2] if len(kind) > 2 else b"")


def _with_opener(opener, fn):
    saved = net._OPENER
    net._OPENER = opener
    try:
        return fn()
    finally:
        net._OPENER = saved


CASES = []


def case(fn):
    CASES.append(fn)
    return fn


@case
def test_file_scheme_refused_without_opening():
    code, final, body = net.check_url("file:///etc/hostname")
    assert (code, final, body) == (0, "file:///etc/hostname", ""), (code, final, body)


@case
def test_ftp_scheme_refused():
    code, final, body = net.check_url("ftp://ftp.example.com/x")
    assert code == 0 and body == ""


@case
def test_link_local_metadata_ip_refused_preflight():
    # No opener installed at all — if it tried to connect, _FakeOpener(None) would blow up.
    def go():
        return net.check_url("http://169.254.169.254/latest/meta-data/")
    code, final, body = _with_opener(_FakeOpener([]), go)
    assert code == 0 and body == "", (code, body)


@case
def test_loopback_ip_and_localhost_refused():
    for u in ("http://127.0.0.1:8080/", "http://localhost/", "http://[::1]/"):
        code, _, _ = _with_opener(_FakeOpener([]), lambda u=u: net.check_url(u))
        assert code == 0, u


@case
def test_validate_url_flags_private_ranges():
    for u in ("http://10.0.0.1/", "http://192.168.1.5/", "http://172.16.9.9/",
              "http://0.0.0.0/", "http://[fd00::1]/", "http://[::1]/",
              "http://foo.local/", "http://foo.localhost/"):
        assert net._validate_url(u) is not None, u


@case
def test_public_ip_literal_allowed():
    assert net._validate_url("http://93.184.216.34/") is None
    assert net._validate_url("https://8.8.8.8/") is None


@case
def test_redirect_into_loopback_is_refused_at_the_hop():
    opener = _FakeOpener([("redirect", "http://127.0.0.1/")])
    code, final, body = _with_opener(
        opener, lambda: net.check_url("http://93.184.216.34/jobs/42"))
    assert code == 0, code
    assert "127.0.0.1" in final, final
    assert body == ""
    assert opener.calls == 1, "must not fetch the loopback target"


@case
def test_redirect_chain_capped():
    # 7 redirects that stay public-looking (literal public IPs) -> refused as too many.
    script = [("redirect", "http://93.184.216.{}/".format(i)) for i in range(2, 10)]
    opener = _FakeOpener(script)
    code, _, _ = _with_opener(
        opener, lambda: net.check_url("http://93.184.216.34/start"))
    assert code == 0
    assert opener.calls <= net.MAX_REDIRECTS + 1, opener.calls


@case
def test_normal_public_get_still_works():
    opener = _FakeOpener([("ok", 200, b"<html>Product Designer - apply</html>")])
    code, final, body = _with_opener(
        opener, lambda: net.check_url("https://93.184.216.34/acme/jobs/123"))
    assert code == 200, code
    assert "product designer" in body


@case
def test_redirect_to_public_is_followed():
    opener = _FakeOpener([
        ("redirect", "https://93.184.216.34/acme/jobs/123?canonical=1"),
        ("ok", 200, b"<html>still live</html>"),
    ])
    code, final, body = _with_opener(
        opener, lambda: net.check_url("https://93.184.216.34/acme/jobs/123"))
    assert code == 200 and "still live" in body
    assert "canonical=1" in final


@case
def test_get_json_refuses_private_target():
    try:
        net.get_json("http://169.254.169.254/latest/")
    except RuntimeError as e:
        assert "refused" in str(e)
    else:
        raise AssertionError("get_json should have refused the link-local target")


def run():
    fails = 0
    for fn in CASES:
        try:
            fn()
        except AssertionError as e:
            fails += 1
            print("  FAIL {}: {}".format(fn.__name__, e))
        except Exception as e:  # noqa: BLE001
            fails += 1
            print("  ERROR {}: {!r}".format(fn.__name__, e))
    print("{}/{} net cases pass".format(len(CASES) - fails, len(CASES)))
    return 1 if fails else 0


if __name__ == "__main__":
    import sys
    sys.exit(run())
