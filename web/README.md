# Rolecall — the `rolecall.io` site

Static marketing + SEO site. Stdlib-only Python generator, consistent with `engine/`.
No pip installs, no build toolchain, no third-party runtime code (the one exception is a
**commented-out** AdSense placeholder on job pages — see below).

## Build

```
python3 -m web build                          # base URL https://rolecall.io
python3 -m web build --base-url https://staging.rolecall.io
```

Reads `../data/board.json` and writes `web/dist/`:

| Path | What | Ads / analytics / cookies |
|---|---|---|
| `index.html` | Landing page — freshness promise, how it works, App Store badge, link to board | none, zero external requests |
| `board/index.html` | Web board — all live roles, vanilla-JS filter (family / remote / text), one **Sponsored role** stub slot | none, zero external requests |
| `jobs/<company>-<title>.html` | One SEO page per role — semantic HTML, canonical, unique title + meta description, JSON-LD `JobPosting`, "Apply on <company>'s site" button, "verified live · <relative time>" | **the single AdSense unit** (commented out) + a minimal cookie notice |
| `sitemap.xml` | landing + board + every job page | |
| `robots.txt` | allow all, points at the sitemap | |
| `board.json` | byte-for-byte copy of `../data/board.json` — the same deploy hosts the app's feed | |
| `_headers` | CORS (`Access-Control-Allow-Origin: *`) + cache-control for `board.json` and pages | |

`dist/` is wiped and rewritten on every build. Rebuild whenever `data/board.json`
is regenerated (wire it into the same cron that runs `python3 -m engine export`).

## Deploy (free tier)

Any static host works. The `_headers` file is written in the Cloudflare Pages / Netlify
format.

### Cloudflare Pages
1. Push the repo. In the Pages dashboard: **Create project → Connect to Git**.
2. Build command: `python3 -m web build`  ·  Build output directory: `web/dist`
   (root directory: repo root, so `../data/board.json` resolves).
3. Deploy. Pages serves `web/dist/` and honours `web/dist/_headers`.

### Netlify
1. **Add new site → Import from Git**.
2. Build command: `python3 -m web build`  ·  Publish directory: `web/dist`.
3. Deploy. Netlify honours `web/dist/_headers`.

### Pointing the `.io` domain
1. Add `rolecall.io` as a custom domain in the host's dashboard.
2. At the registrar, set the nameservers to the host's (Cloudflare), **or** add the
   records the host shows — typically `CNAME www → <project>.pages.dev` and an
   apex `A`/`ALIAS`/flattened `CNAME` to the host.
3. Wait for DNS + the auto-provisioned TLS cert. Confirm `https://rolecall.io/board.json`
   returns JSON with `Access-Control-Allow-Origin: *` (the iOS app depends on this).
4. Rebuild with the real base URL if it ever differs from `https://rolecall.io`
   (the canonical tags and sitemap bake it in).

## AdSense — job pages only

The Fellows' monetization ruling, implemented here:

- The **iOS app is ad-free / tracker-free forever.** It is a different trust surface.
- AdSense pays per pageview, which quietly rewards keeping people browsing — the
  opposite of the product North Star ("get hired fast and leave"). So it is capped to
  **one unobtrusive unit, on job-detail pages only. Never on the landing page or the
  board index.**
- Site job #1 is the funnel to the app. Job #2 is SEO. AdSense is a distant third.
- Higher-value web revenue is **employer-sponsored listings** ("feature your role at the
  top for a week") — stubbed as the labelled slot at the top of the board.

### Turning AdSense on
1. Get the publisher ID (`ca-pub-................`) and an ad-slot ID from AdSense.
2. In `web/build.py`, set `ADSENSE_CLIENT` and `ADSENSE_SLOT`.
3. In the job-page template in `web/build.py`, uncomment the three lines inside the
   `<!-- ADSENSE SLOT: single unit, job pages only -->` block.
4. Rebuild. Only `jobs/*.html` will load AdSense; the cookie notice on those pages is
   already wired. Do **not** add the unit to any other page type.

## Design decisions

- **System font stack**, no web fonts. Light + dark via `prefers-color-scheme`.
  Responsive, single stylesheet inlined in every page.
- Landing + board make **zero external requests** — Lighthouse-clean, works offline,
  no CDN, no analytics, no Tag Manager.
- Board roles are **server-rendered**; the JS only shows/hides DOM nodes, so the board
  works with JS disabled and needs no `fetch`.
- Job pages carry **JSON-LD `JobPosting`** — the real prize: eligibility for the Google
  Jobs rich result, which sends candidates straight to the company's own posting
  (source-direct, per the product North Star). Location strings are parsed best-effort
  into `schema.org` `Place` / `PostalAddress`; remote roles get `jobLocationType:
  TELECOMMUTE` + `applicantLocationRequirements`.
- The cookie notice appears on **job pages only**, because that is the only page type
  that can set a cookie (via AdSense, when enabled).

## Still open

- Real AdSense publisher ID + ad-slot ID (`ADSENSE_CLIENT` / `ADSENSE_SLOT`).
- Real App Store URL (`APP_STORE_URL` in `web/build.py`) — placeholder `#app-store-link-tbd`.
- `sponsors@rolecall.io` mailbox (or change `SPONSOR_CONTACT`).
- Domain DNS + TLS at the host.
- Optional: an App Store badge image (currently a CSS/inline-SVG pill to avoid an
  external request) and OG share image.
