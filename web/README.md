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
| `board.json` | the **full** `../data/board.json` — the same deploy hosts the iOS app's feed (the app does its own filtering) | |
| `CNAME` | `rolecall.io` — binds the GitHub Pages custom domain | |
| `.nojekyll` | stops GitHub Pages' Jekyll from dropping `_`-prefixed files | |
| `_headers` | CORS + cache-control — honoured by Cloudflare/Netlify, **ignored by GitHub Pages** (the iOS app doesn't need CORS; the web board never `fetch`es) | |

The **rendered pages** show the same slice the app leads with: the product-design
vertical (design · design-eng · research; **PM excluded**), US + US-remote. The copied
`board.json` stays the full board so the app's own PM / worldwide toggles work.

`dist/` is wiped and rewritten on every build.

## Deploy — Cloudflare Pages (current)

`.github/workflows/pages.yml` runs on push to `main` (when `web/` or `engine/` changes),
on a 6-hourly cron, and on manual dispatch. It ingests a fresh board, exports it, builds
`web/dist/`, and deploys it to Cloudflare Pages with `wrangler`. The engine's SQLite DB is
cached between runs so `first_seen` (and "new today") stays stable. Cloudflare honours the
`_headers` file, so `board.json` is served CORS-open and briefly cached.

**One-time setup:**
1. In Cloudflare: **Workers & Pages → Create → Pages → "Use direct upload"** and name the
   project **`rolecall`** (or run `npx wrangler pages project create rolecall
   --production-branch main`).
2. **My Profile → API Tokens → Create Token**, template *"Edit Cloudflare Workers"* — or a
   custom token with **Account · Cloudflare Pages · Edit**. Copy it.
3. Repo → **Settings → Secrets and variables → Actions → New repository secret**:
   - `CLOUDFLARE_API_TOKEN` — the token from step 2
   - `CLOUDFLARE_ACCOUNT_ID` — from any Cloudflare dashboard URL, or `wrangler whoami`
4. Push (or **Actions → Deploy rolecall.io → Run workflow**). Until the secrets exist the
   workflow still builds and just skips the deploy with a warning.
5. First deploy lands at `https://rolecall.pages.dev`.

### Pointing `rolecall.io` at it
1. Add `rolecall.io` to the Cloudflare account (**Add a site**) and move the registrar's
   nameservers to the ones Cloudflare shows — DNS then becomes one-click.
2. Pages project → **Custom domains → Set up a domain → `rolecall.io`** (and `www`).
   Cloudflare creates the records and the cert automatically.
3. Set the repo **Actions variable** `SITE_BASE_URL` to `https://rolecall.io`, then re-run
   the workflow so canonical tags / sitemap / links bake in the real origin.
4. Confirm `https://rolecall.io/board.json` returns JSON (the iOS app reads it there).

### Alternatives (same `dist/`, same `_headers`)
- **Netlify:** *Add new site → Import from Git*, publish directory `web/dist`, or drag-drop
  `web/dist/`.
- **Cloudflare Git integration** (no Actions): *Create project → Connect to Git*, build
  command `python3 -m engine ingest && python3 -m engine export && python3 -m web build`,
  output `web/dist`. Loses the engine-state cache, so `first_seen` resets each build.

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
