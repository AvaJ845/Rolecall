"""Run: python -m engine.tests.test_log_privacy

`verify` must not print full posting URLs to CI logs by default — the
6-hourly build history would otherwise be a timestamped "who is hiring designers"
record if the repo is ever made public. `--verbose` (never passed by CI) restores
full URLs for local debugging.
"""
from __future__ import annotations

from engine import __main__ as cli
from engine import verify

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


@case
def test_short_url_drops_query_and_truncates_path():
    s = verify._short_url(
        "https://boards.greenhouse.io/acme/jobs/4567890?utm_source=x&gh_jid=4567890")
    assert "boards.greenhouse.io" in s
    assert "?" not in s and "utm_source" not in s and "4567890" not in s
    assert len(s) <= len("boards.greenhouse.io") + 17


@case
def test_short_url_keeps_short_paths_whole():
    assert verify._short_url("https://jobs.lever.co/acme") == "jobs.lever.co/acme"


@case
def test_short_url_handles_garbage():
    assert verify._short_url("") == "?/"
    # never raises, never returns something with a scheme/query
    out = verify._short_url("http://x/a?b=c#d")
    assert "?" not in out and "#" not in out


@case
def test_verify_signature_defaults_to_non_verbose():
    # The CI invocation is `python3 -m engine verify 250` — no -v.
    import inspect

    sig = inspect.signature(verify.verify)
    assert sig.parameters["verbose"].default is False


@case
def test_cli_parses_verbose_flag_and_limit(monkeypatch=None):
    calls = {}

    def fake_verify(limit=300, min_age_hours=0.0, verbose=False):
        calls["limit"] = limit
        calls["verbose"] = verbose
        return 0

    saved = verify.verify
    verify.verify = fake_verify
    try:
        cli.main(["verify", "250"])
        assert calls == {"limit": 250, "verbose": False}, calls
        cli.main(["verify", "250", "--verbose"])
        assert calls == {"limit": 250, "verbose": True}, calls
        cli.main(["verify", "-v"])
        assert calls == {"limit": 300, "verbose": True}, calls
    finally:
        verify.verify = saved


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
    print("{}/{} log-privacy cases pass".format(len(CASES) - fails, len(CASES)))
    return 1 if fails else 0


if __name__ == "__main__":
    import sys
    sys.exit(run())
