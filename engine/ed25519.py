"""
Minimal pure-Python Ed25519 (RFC 8032), vendored so `engine/` stays stdlib-only.

Adapted from the public-domain reference implementation at https://ed25519.cr.yp.to/
(Bernstein et al.) + the RFC 8032 test vectors. Only what Rolecall needs: keygen,
detached sign, verify. It signs one small file per publish, so performance is a non-issue.
"""
from __future__ import annotations

import hashlib
import os

b = 256
q = 2 ** 255 - 19
L = 2 ** 252 + 27742317777372353535851937790883648493


def _H(m: bytes) -> bytes:
    return hashlib.sha512(m).digest()


def _inv(x: int) -> int:
    return pow(x, q - 2, q)


d = -121665 * _inv(121666) % q
I = pow(2, (q - 1) // 4, q)


def _xrecover(y: int) -> int:
    xx = (y * y - 1) * _inv(d * y * y + 1)
    x = pow(xx, (q + 3) // 8, q)
    if (x * x - xx) % q != 0:
        x = (x * I) % q
    if x % 2 != 0:
        x = q - x
    return x


By = 4 * _inv(5) % q
Bx = _xrecover(By) % q
B = (Bx % q, By % q, 1, (Bx * By) % q)
ident = (0, 1, 1, 0)


def _edwards_add(P, Q):
    x1, y1, z1, t1 = P
    x2, y2, z2, t2 = Q
    a = (y1 - x1) * (y2 - x2) % q
    c = (y1 + x1) * (y2 + x2) % q
    e = 2 * t1 * t2 * d % q
    f = 2 * z1 * z2 % q
    g = f - e
    h = f + e
    e2 = c - a
    f2 = g
    g2 = h
    h2 = c + a
    return (e2 * f2 % q, g2 * h2 % q, f2 * g2 % q, e2 * h2 % q)


def _scalarmult(P, e):
    if e == 0:
        return ident
    Q = _scalarmult(P, e // 2)
    Q = _edwards_add(Q, Q)
    if e & 1:
        Q = _edwards_add(Q, P)
    return Q


def _encodeint(y: int) -> bytes:
    return y.to_bytes(b // 8, "little")


def _encodepoint(P) -> bytes:
    x, y, z, _ = P
    zi = _inv(z)
    x = x * zi % q
    y = y * zi % q
    bits = [(y >> i) & 1 for i in range(b - 1)] + [x & 1]
    return bytes(sum(bits[i * 8 + j] << j for j in range(8)) for i in range(b // 8))


def _bit(h: bytes, i: int) -> int:
    return (h[i // 8] >> (i % 8)) & 1


def publickey(sk: bytes) -> bytes:
    h = _H(sk)
    a = 2 ** (b - 2) + sum(2 ** i * _bit(h, i) for i in range(3, b - 2))
    A = _scalarmult(B, a)
    return _encodepoint(A)


def keygen() -> tuple[bytes, bytes]:
    sk = os.urandom(32)
    return sk, publickey(sk)


def sign(msg: bytes, sk: bytes, pk: bytes | None = None) -> bytes:
    if pk is None:
        pk = publickey(sk)
    h = _H(sk)
    a = 2 ** (b - 2) + sum(2 ** i * _bit(h, i) for i in range(3, b - 2))
    r = int.from_bytes(_H(h[b // 8:b // 4] + msg), "little")
    R = _scalarmult(B, r)
    Renc = _encodepoint(R)
    k = int.from_bytes(_H(Renc + pk + msg), "little")
    s = (r + k * a) % L
    return Renc + _encodeint(s)


def _decodepoint(s: bytes):
    y = int.from_bytes(s, "little") & ((1 << (b - 1)) - 1)
    x = _xrecover(y)
    if x & 1 != _bit(s, b - 1):
        x = q - x
    P = (x, y, 1, (x * y) % q)
    if not _isoncurve(P):
        raise ValueError("decoding point that is not on curve")
    return P


def _isoncurve(P) -> bool:
    x, y, z, t = P
    return (
        z % q != 0
        and x * y % q == z * t % q
        and (y * y - x * x - z * z - d * t * t) % q == 0
    )


def verify(sig: bytes, msg: bytes, pk: bytes) -> bool:
    if len(sig) != b // 4 or len(pk) != b // 8:
        return False
    try:
        R = _decodepoint(sig[:b // 8])
        A = _decodepoint(pk)
    except ValueError:
        return False
    s = int.from_bytes(sig[b // 8:b // 4], "little")
    k = int.from_bytes(_H(sig[:b // 8] + pk + msg), "little")
    x1, y1, z1, _ = _scalarmult(B, s)
    x2, y2, z2, _ = _edwards_add(R, _scalarmult(A, k))
    return (x1 * z2 - x2 * z1) % q == 0 and (y1 * z2 - y2 * z1) % q == 0
