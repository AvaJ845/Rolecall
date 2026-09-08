"""
Sign the published board so the iOS app can prove it came from us — not a compromised
CDN or a MITM that slipped past TLS.

  python3 -m engine keygen                 # once — prints a private key + public key
  python3 -m engine sign                   # signs data/board.json -> data/board.json.sig

`sign` reads the 64-hex-char private key from the ROLECALL_SIGNING_KEY env var (a GitHub
Actions secret in CI). The public key is committed at engine/board_pubkey.hex and is also
compiled into the app (BoardSource.publicKeyHex) — the two must match.

The signature is over the exact bytes of data/board.json. board.json.sig is the raw
64-byte Ed25519 signature, hex-encoded, one line.
"""
from __future__ import annotations

import json
import os
import pathlib

from . import ed25519

ROOT = pathlib.Path(__file__).resolve().parent.parent
BOARD = ROOT / "data" / "board.json"
SIG = ROOT / "data" / "board.json.sig"
# P0-7: board + signature as ONE artifact the app fetches in one request, so the edge
# can never serve a new board against a stale cached signature (the 4x/day deploy skew).
# `board` is the *exact text* of board.json embedded as a JSON string — decode it, UTF-8
# it, and you have byte-for-byte what `sig` signs. No canonicalisation, no ambiguity.
BOARD_V2 = ROOT / "data" / "board.v2.json"
PUBKEY_FILE = pathlib.Path(__file__).resolve().parent / "board_pubkey.hex"


def keygen() -> int:
    sk, pk = ed25519.keygen()
    print("PRIVATE KEY (keep secret — set as ROLECALL_SIGNING_KEY):")
    print("  " + sk.hex())
    print("PUBLIC KEY (commit to engine/board_pubkey.hex and BoardSource.publicKeyHex):")
    print("  " + pk.hex())
    return 0


def sign() -> int:
    if not BOARD.exists():
        print("error: {} not found — run `python3 -m engine export` first".format(BOARD))
        return 1
    key_hex = os.environ.get("ROLECALL_SIGNING_KEY", "").strip()
    if len(key_hex) != 64:
        print("error: set ROLECALL_SIGNING_KEY to the 64-hex-char private key")
        return 1
    sk = bytes.fromhex(key_hex)
    pk = ed25519.publickey(sk)

    if PUBKEY_FILE.exists():
        expected = PUBKEY_FILE.read_text().strip()
        if expected and expected != pk.hex():
            print("error: signing key does not match engine/board_pubkey.hex")
            print("  key's public : {}".format(pk.hex()))
            print("  committed    : {}".format(expected))
            return 1
    else:
        PUBKEY_FILE.write_text(pk.hex() + "\n")
        print("wrote {} (commit this)".format(PUBKEY_FILE))

    data = BOARD.read_bytes()
    signature = ed25519.sign(data, sk, pk)
    assert ed25519.verify(signature, data, pk), "self-verify failed"
    SIG.write_text(signature.hex() + "\n")
    print("signed {} bytes -> {}".format(len(data), SIG))

    # P0-7: the single-artifact envelope. board.json is ASCII (json.dumps ensure_ascii),
    # so board_text.encode("utf-8") == data exactly — the signature still covers the exact
    # bytes. Written as compact JSON; the app fetches this one URL.
    board_text = data.decode("utf-8")
    envelope = json.dumps({"format": 2, "sig": signature.hex(), "board": board_text},
                          separators=(",", ":"))
    assert json.loads(envelope)["board"].encode("utf-8") == data, "envelope round-trip"
    BOARD_V2.write_text(envelope)
    print("wrote single-artifact envelope -> {}".format(BOARD_V2))
    return 0
