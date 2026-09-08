"""
Rolecall engine — pulls each company's own public ATS feed, classifies to the
product-design vertical, tracks liveness, and exports the signed board the app trusts.

    python -m engine doctor            # do all seed slugs resolve and return roles?
    python -m engine resolve           # re-probe every slug; report ATS migrations
    python -m engine ingest            # pull feeds, classify, track freshness
    python -m engine verify [N] [-v]   # HTTP-check up to N live postings (-v: full URLs)
    python -m engine audit [N]         # hand-check N; prints verified-live accuracy
    python -m engine stats             # snapshot
    python -m engine export            # data/board.json
    python -m engine sign              # data/board.json.sig  (needs ROLECALL_SIGNING_KEY)
    python -m engine keygen            # print a new signing keypair (once)

Each command lives in its own module (ingest.py, verify.py, resolve.py, report.py,
export.py); this file only dispatches. `python -m engine.tests` runs the test suite.
"""
from __future__ import annotations

import sys

from . import export as _export
from . import ingest as _ingest
from . import report as _report
from . import resolve as _resolve
from . import sign as _sign
from . import verify as _verify
from .registry import RegistryError


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    cmd, rest = argv[0], argv[1:]
    try:
        if cmd == "doctor":
            return _ingest.doctor()
        if cmd == "resolve":
            return _resolve.resolve()
        if cmd == "ingest":
            return _ingest.ingest()
        if cmd == "verify":
            verbose = any(a in ("-v", "--verbose") for a in rest)
            pos = [a for a in rest if not a.startswith("-")]
            return _verify.verify(limit=int(pos[0]) if pos else 300, verbose=verbose)
        if cmd == "audit":
            return _report.audit(sample=int(rest[0]) if rest else 25)
        if cmd == "stats":
            return _report.stats()
        if cmd == "export":
            return _export.export()
        if cmd == "sign":
            return _sign.sign()
        if cmd == "keygen":
            return _sign.keygen()
    except RegistryError as e:
        print("::error::companies.json is invalid: {}".format(e))
        print("error: {}".format(e))
        return 2
    print("unknown command: {}\n".format(cmd))
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
