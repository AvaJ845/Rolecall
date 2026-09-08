"""
Rolecall web — the rolecall.io marketing + SEO static site.

    python3 -m web build [--base-url https://rolecall.io]

Reads ../data/board.json and writes web/dist/:
  index.html                     landing page   (no ads, no analytics, no cookies)
  board/index.html               web board      (client-side filter, sponsored slot)
  jobs/<company>-<title>.html    one SEO page per role, JSON-LD JobPosting,
                                 the single AdSense slot + cookie notice
  sitemap.xml, robots.txt
  board.json                     copy of the app feed (same deploy hosts it)
  _headers                       CORS + cache-control for board.json

Stdlib only. Runs on system python3 (3.9+). No pip, no network, no CDN.
"""
from __future__ import annotations

import sys

from . import build


def main(argv):
    if not argv or argv[0] in ("-h", "--help", "help"):
        print(__doc__)
        return 0
    if argv[0] == "build":
        return build.main(argv[1:])
    print("unknown command: {}\n".format(argv[0]))
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
