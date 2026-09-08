"""Run: python -m engine.tests.test_sign_envelope

P0-7: `engine sign` also writes data/board.v2.json — a single artifact
{ "format": 2, "sig": "<hex>", "board": "<exact board.json text>" } so the app
fetches the board and its signature in one request (no deploy-window skew). The
embedded board text's UTF-8 bytes must equal board.json byte-for-byte, and the
signature must verify over them.
"""
from __future__ import annotations

import json
import os
import pathlib
import tempfile

from engine import ed25519
from engine import sign as sign_mod

CASES = []


def case(fn):
    CASES.append(fn)
    return fn


def _run_sign(board_bytes):
    d = tempfile.mkdtemp()
    board = pathlib.Path(d) / "board.json"
    board.write_bytes(board_bytes)
    sk, pk = ed25519.keygen()
    saved = (sign_mod.BOARD, sign_mod.SIG, sign_mod.BOARD_V2, sign_mod.PUBKEY_FILE)
    sign_mod.BOARD = board
    sign_mod.SIG = pathlib.Path(d) / "board.json.sig"
    sign_mod.BOARD_V2 = pathlib.Path(d) / "board.v2.json"
    sign_mod.PUBKEY_FILE = pathlib.Path(d) / "pub.hex"
    sign_mod.PUBKEY_FILE.write_text(pk.hex() + "\n")
    os.environ["ROLECALL_SIGNING_KEY"] = sk.hex()
    try:
        rc = sign_mod.sign()
        return rc, sign_mod.SIG, sign_mod.BOARD_V2, pk
    finally:
        del os.environ["ROLECALL_SIGNING_KEY"]
        sign_mod.BOARD, sign_mod.SIG, sign_mod.BOARD_V2, sign_mod.PUBKEY_FILE = saved


@case
def test_envelope_bytes_match_board_and_signature_verifies():
    board_bytes = json.dumps(
        {"generated_utc": 1.0, "count": 1, "meta": {"vertical": "product-design"},
         "roles": [{"company": "Café Motörhead", "title": "Designer",
                    "url": "https://x/1"}]},
        indent=2,
    ).encode("utf-8")
    # json.dumps default ensure_ascii -> board.json is pure ASCII even with accents
    assert board_bytes.isascii()

    rc, sig_path, v2_path, pk = _run_sign(board_bytes)
    assert rc == 0

    env = json.loads(v2_path.read_text())
    assert env["format"] == 2
    assert env["board"].encode("utf-8") == board_bytes, "embedded board must be byte-exact"
    assert env["sig"] == sig_path.read_text().strip(), "envelope sig == detached sig file"
    assert ed25519.verify(bytes.fromhex(env["sig"]), env["board"].encode("utf-8"), pk)


@case
def test_envelope_is_compact_single_line():
    rc, _, v2_path, _ = _run_sign(b'{"generated_utc":1.0,"count":0,"roles":[]}')
    assert rc == 0
    text = v2_path.read_text()
    assert "\n" not in text.strip()
    assert ": " not in text and ", " not in text  # separators=(",", ":")


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
    print("{}/{} sign-envelope cases pass".format(len(CASES) - fails, len(CASES)))
    return 1 if fails else 0


if __name__ == "__main__":
    import sys
    sys.exit(run())
