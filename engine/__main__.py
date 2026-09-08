"""
Rolecall engine — Week-0 verification spike.

    python -m engine doctor            # do all seed slugs resolve?
    python -m engine resolve           # re-probe every slug; report ATS migrations
    python -m engine ingest            # pull feeds, classify, track freshness
    python -m engine verify [N]        # HTTP-check up to N live postings
    python -m engine audit [N]         # hand-check N; prints verified-live accuracy
    python -m engine stats             # snapshot
    python -m engine export            # data/board.json
    python -m engine sign              # data/board.json.sig  (needs ROLECALL_SIGNING_KEY)
    python -m engine keygen            # print a new signing keypair (once)
"""
from __future__ import annotations

import sys

from . import pipeline
from . import sign as _sign


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    cmd, rest = argv[0], argv[1:]
    if cmd == "doctor":
        return pipeline.doctor()
    if cmd == "resolve":
        return pipeline.resolve()
    if cmd == "ingest":
        return pipeline.ingest()
    if cmd == "verify":
        return pipeline.verify(limit=int(rest[0]) if rest else 300)
    if cmd == "audit":
        return pipeline.audit(sample=int(rest[0]) if rest else 25)
    if cmd == "stats":
        return pipeline.stats()
    if cmd == "export":
        return pipeline.export()
    if cmd == "sign":
        return _sign.sign()
    if cmd == "keygen":
        return _sign.keygen()
    print("unknown command: {}\n".format(cmd))
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
