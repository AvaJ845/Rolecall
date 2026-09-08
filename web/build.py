"""Static site generator for rolecalljobs.com — stdlib only.

Design intent (see NORTH_STARS.md and the Fellows' monetization ruling):
  * Site job #1 is the funnel to the iOS app; job #2 is SEO; ads are a distant third.
  * The landing page and the board index carry NO ads, NO analytics, NO cookies,
    and make ZERO external requests.
  * Job-detail pages are the ONLY page type that may carry the single AdSense unit
    (commented-out placeholder here) and therefore the only ones with a cookie notice.
  * Employer-sponsored listings are the higher-value web revenue; the board carries
    a clearly-marked stub slot for them.
"""
from __future__ import annotations

import argparse
import html
import json
import pathlib
import re
import shutil
import time
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parent.parent
BOARD_PATH = ROOT / "data" / "board.json"
WEB = ROOT / "web"
DIST = WEB / "dist"

DEFAULT_BASE_URL = "https://rolecalljobs.com"

# --------------------------------------------------------------------------
# AdSense — paste the real publisher id here, then uncomment the slot markup
# in the job-page template below. This is the ONLY third-party anything on the
# whole site, and it appears on job-detail pages only. Never on the landing
# page, never on the board index.
ADSENSE_CLIENT = "ca-pub-XXXXXXXXXXXXXXXX"
ADSENSE_SLOT = "0000000000"
# --------------------------------------------------------------------------

SPONSOR_CONTACT = "sponsors@rolecalljobs.com"
SUPPORT_CONTACT = "support@rolecalljobs.com"
APP_STORE_URL = "#app-store-link-tbd"  # replace with the real App Store URL at launch

FAMILY_LABEL = {
    "design": "Design",
    "design-eng": "Design Engineering",
    "pm": "Product Management",
    "research": "UX Research",
}
FAMILY_ORDER = ["design", "design-eng", "research", "pm"]

esc = html.escape


def family_label(fam: str) -> str:
    return FAMILY_LABEL.get(fam, (fam or "Other").replace("-", " ").title())


def slugify(text: str, maxlen: int = 70) -> str:
    text = (text or "").lower().replace("&", " and ")
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    if len(text) > maxlen:
        text = text[:maxlen].rsplit("-", 1)[0]
    return text or "role"


def iso_date(ts: float) -> str:
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%d")


def iso_dt(ts: float) -> str:
    return datetime.fromtimestamp(ts, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")


# The public site tells the same story as the app: the product-design vertical, US +
# US-remote. PM roles are classified by the engine but stay off the board.
_DESIGN_FAMILIES = {"design", "design-eng", "research"}
_NON_US = (
    "united kingdom", "england", "london", "canada", "toronto", "vancouver", "ontario",
    "germany", "berlin", "munich", "france", "paris", "netherlands", "amsterdam",
    "ireland", "dublin", "singapore", "australia", "sydney", "melbourne", "india",
    "bangalore", "bengaluru", "hyderabad", "israel", "tel aviv", "spain", "barcelona",
    "madrid", "poland", "warsaw", "brazil", "ão paulo", "sao paulo", "japan", "tokyo",
    "milan", "italy", "rome", "sweden", "stockholm", "portugal", "lisbon", "mexico",
    "emea", "apac", "latam", "switzerland", "zurich", "denmark", "copenhagen",
    "norway", "oslo", "finland", "helsinki", "belgium", "brussels", "austria", "vienna",
)
_US_HINT = (
    "united states", "usa", "u.s", "remote", "anywhere", "san francisco", "new york",
    "nyc", "seattle", "austin", "chicago", "boston", "los angeles", "denver", "atlanta",
    "portland", "miami", "washington", "brooklyn",
)


def in_scope(role: dict) -> bool:
    if role.get("family") not in _DESIGN_FAMILIES:
        return False
    if role.get("remote") is True:
        return True
    loc = (role.get("location") or "").lower()
    if not loc:
        return True
    if any(h in loc for h in _US_HINT):
        return True
    return not any(h in loc for h in _NON_US)


def rel_time(ts, now: float) -> str:
    if not ts:
        return "recently"
    d = max(0.0, now - ts)
    if d < 90:
        return "just now"
    if d < 3600:
        return "{}m ago".format(int(d // 60))
    if d < 86400:
        return "{}h ago".format(int(d // 3600))
    return "{}d ago".format(int(d // 86400))


def employment_type(title: str) -> str:
    if re.search(r"\bintern(ship)?\b", title or "", re.I):
        return "INTERN"
    if re.search(r"\bcontract(or)?\b|\bfixed[- ]term\b", title or "", re.I):
        return "CONTRACTOR"
    return "FULL_TIME"


def guess_country(location: str):
    lt = (location or "").lower()
    if "united states" in lt or re.search(r"\bu\.?s\.?a?\b", lt):
        return "United States"
    if "united kingdom" in lt or re.search(r"\bu\.?k\.?\b", lt) or "london" in lt:
        return "United Kingdom"
    if "canada" in lt or "toronto" in lt or "vancouver" in lt:
        return "Canada"
    return None


def parse_locations(location: str):
    """Best-effort schema.org Place list from a free-text location string."""
    if not location:
        return []
    places = []
    for part in re.split(r"\s*(?:;|/| or |\|)\s*", location):
        part = re.sub(r"\(.*?\)", "", part).strip().strip(",").strip()
        if not part or "remote" in part.lower() or "anywhere" in part.lower():
            continue
        seg = [s.strip() for s in part.split(",") if s.strip()]
        if not seg:
            continue
        addr = {"@type": "PostalAddress"}
        if len(seg) == 1:
            addr["addressLocality"] = seg[0]
            c = guess_country(seg[0])
            if c:
                addr["addressLocality"] = seg[0]
                addr["addressCountry"] = c
        elif len(seg) == 2:
            addr["addressLocality"] = seg[0]
            if re.fullmatch(r"[A-Z]{2}", seg[1]) or re.fullmatch(r"[A-Z]\.[A-Z]\.?", seg[1]):
                addr["addressRegion"] = seg[1]
                addr["addressCountry"] = "United States"
            else:
                addr["addressRegion"] = seg[1]
                c = guess_country(seg[1])
                if c:
                    addr["addressCountry"] = c
        else:
            addr["addressLocality"] = seg[0]
            addr["addressRegion"] = seg[1]
            addr["addressCountry"] = guess_country(seg[-1]) or seg[-1]
        places.append({"@type": "Place", "address": addr})
    return places


# --------------------------------------------------------------------------
# Shared shell
# --------------------------------------------------------------------------

CSS = """
*,*::before,*::after{box-sizing:border-box}
:root{
  --bg:#F6F3EC; --panel:#FFFFFF; --ink:#2C2823; --muted:#6B6357; --faint:#938A7B;
  --line:#E6E0D3; --tint:#EFE1DA; --accent:#AA5C4A; --accent2:#B65E48;
  --verified:#3F6B4A; --link:#9A5140;
  --hero1:#2C2823; --hero2:#3B2A21;
  --maxw:1040px;
}
@media (prefers-color-scheme:dark){
  :root{
    --bg:#17150F; --panel:#221E17; --ink:#EFE9DD; --muted:#A79E8D; --faint:#7C7364;
    --line:#332E24; --tint:#2E211C; --accent:#D4856B; --accent2:#E0906F;
    --verified:#8FC79B; --link:#E0906F;
    --hero1:#100E0A; --hero2:#241A14;
  }
}
html{scroll-behavior:smooth;-webkit-text-size-adjust:100%}
body{margin:0;background:var(--bg);color:var(--ink);
  font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,"Segoe UI",Roboto,sans-serif;
  -webkit-font-smoothing:antialiased;line-height:1.55}
.wrap{max-width:var(--maxw);margin:0 auto;padding:0 22px}
a{color:var(--link);text-decoration:none}
a:hover{text-decoration:underline}
code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.9em;
  background:var(--tint);padding:.1em .35em;border-radius:.3em}

/* serif display, matching the app */
h1,h2,h3{font-family:ui-serif,Georgia,"Times New Roman",serif;font-weight:600;
  letter-spacing:-.01em;line-height:1.2;margin:0 0 .4em;text-wrap:balance}

/* topbar on inner pages only */
.topbar{border-bottom:1px solid var(--line);background:var(--bg)}
.topbar .wrap{display:flex;align-items:center;justify-content:space-between;height:58px}
.topbar .brand{font-family:ui-serif,Georgia,serif;font-weight:600;font-size:19px;color:var(--ink)}
.topbar .brand:hover{text-decoration:none}
.topbar nav a{color:var(--muted);font-size:14px;margin-left:20px}

/* hero */
.hero{background:linear-gradient(160deg,var(--hero1),var(--hero2));color:#F6EFE6;
  padding:78px 0 64px;text-align:center}
.hero .wrap{display:flex;flex-direction:column;align-items:center;gap:15px}
.appicon{width:96px;height:96px;border-radius:22px;box-shadow:0 14px 34px rgba(0,0,0,.35)}
.hero h1{font-size:clamp(34px,6vw,52px);margin:6px 0 0;color:#F6EFE6}
.hero .tagline{font-size:clamp(17px,2.6vw,21px);color:#E4D3C6;max-width:30ch;margin:0}
.hero .sub{color:#C0AC9F;max-width:56ch;margin:0;font-size:15px;line-height:1.6}
.cta{display:inline-flex;align-items:center;gap:9px;background:var(--accent2);color:#FFF6F1;
  padding:14px 28px;border-radius:999px;font-weight:700;font-size:16px;
  box-shadow:0 12px 28px rgba(170,92,74,.42)}
.cta:hover{filter:brightness(1.06);text-decoration:none}
.cta svg{width:18px;height:18px;fill:currentColor}
.ctanote{color:#B39B8D;font-size:13px;margin:2px 0 0;max-width:46ch}
.pill{margin-top:6px;display:inline-flex;align-items:center;gap:8px;
  background:rgba(255,255,255,.10);border:1px solid rgba(255,255,255,.22);
  color:#F6EFE6;padding:9px 17px;border-radius:999px;font-weight:600;font-size:14px}
.dot{width:8px;height:8px;border-radius:50%;background:var(--accent2);
  box-shadow:0 0 0 4px rgba(212,133,107,.25)}
.price{color:#B39B8D;font-size:13.5px;margin:4px 0 0}

/* sections */
section{padding:58px 0}
section.tight{padding-top:0}
h2{font-size:clamp(24px,4vw,32px);text-align:center}
.lead{color:var(--muted);text-align:center;max-width:62ch;margin:0 auto 32px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:18px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:18px;padding:24px}
.card h3{margin:0 0 6px;font-size:17px}
.card p{margin:0;color:var(--muted);font-size:14.5px}
.ic{width:40px;height:40px;border-radius:11px;display:grid;place-items:center;
  margin-bottom:14px;background:var(--tint);color:var(--accent);font-size:20px}

.claim{background:var(--panel);border:1px solid var(--line);border-radius:22px;
  padding:30px;max-width:820px;margin:0 auto}
.claim ul{margin:14px 0 0;padding-left:1.1rem;color:var(--muted)}
.claim li{margin:8px 0}
.claim li strong{color:var(--ink)}
.pledge{background:var(--panel);border:1px solid var(--line);border-radius:22px;
  padding:32px;text-align:center;max-width:760px;margin:0 auto}
.pledge strong{color:var(--verified)}

.steps{counter-reset:s;display:grid;gap:14px;max-width:660px;margin:0 auto}
.step{background:var(--panel);border:1px solid var(--line);border-radius:14px;
  padding:18px 20px;display:flex;gap:14px;align-items:flex-start}
.step::before{counter-increment:s;content:counter(s,decimal-leading-zero);flex:0 0 auto;
  font-family:ui-serif,Georgia,serif;color:var(--accent);font-weight:600;font-size:15px;
  min-width:26px}
.step b{color:var(--ink)}
.step p{margin:0;color:var(--muted);font-size:14.5px}

.cta-block{text-align:center;padding:8px 0 4px}

/* board */
h1.page{font-family:ui-serif,Georgia,serif;font-size:clamp(28px,5vw,40px);margin:26px 0 4px}
.small{font-size:13.5px;color:var(--muted)}
.btn{display:inline-block;background:var(--accent2);color:#FFF6F1;padding:12px 22px;
  border-radius:999px;font-weight:600;font-size:15px;border:1px solid var(--accent2)}
.btn:hover{text-decoration:none;filter:brightness(1.05)}
.btn.ghost{background:transparent;color:var(--ink);border-color:var(--line)}
.sponsored{border:1px dashed var(--faint);border-radius:14px;padding:16px 18px;
  margin:18px 0;background:var(--tint)}
.spon-label,.ad-label{display:inline-block;font-size:11px;font-weight:700;letter-spacing:.1em;
  text-transform:uppercase;color:var(--faint);margin-bottom:6px}
.sponsored p{margin:0;font-size:14px;color:var(--muted)}
.toolbar{display:flex;flex-wrap:wrap;gap:10px;align-items:center;
  padding:14px 0 16px;border-bottom:1px solid var(--line);margin-bottom:16px}
.toolbar input[type=search],.toolbar select{font:inherit;font-size:14px;padding:9px 12px;
  border:1px solid var(--line);border-radius:10px;background:var(--panel);color:var(--ink)}
.toolbar input[type=search]{flex:1 1 12rem;min-width:0}
.toolbar label.chk{display:inline-flex;align-items:center;gap:6px;font-size:14px;color:var(--muted)}
.count{color:var(--muted);font-size:13px;margin-left:auto}
ul.roles{list-style:none;margin:0;padding:0;display:grid;gap:10px}
li.role{border:1px solid var(--line);border-radius:14px;background:var(--panel)}
li.role a.role-link{display:block;padding:16px 18px;color:var(--ink)}
li.role a.role-link:hover{text-decoration:none;border-color:var(--faint)}
.role .co{font-size:13px;color:var(--muted);font-weight:600}
.role .ti{font-family:ui-serif,Georgia,serif;font-size:18px;font-weight:600;margin:3px 0 6px}
.role .mt{font-size:13px;color:var(--muted);display:flex;flex-wrap:wrap;gap:6px 14px;align-items:center}
.tag{display:inline-block;font-size:11.5px;font-weight:600;padding:2px 9px;border-radius:999px;
  background:var(--tint);color:var(--muted)}
.empty{padding:48px 0;text-align:center;color:var(--muted)}

/* job detail */
.job-head{padding:26px 0 10px}
.job-head .co{font-size:14px;color:var(--muted);font-weight:600}
.job-head h1{font-size:clamp(24px,4vw,34px);margin:6px 0 12px}
.verified{display:inline-flex;align-items:center;gap:7px;font-size:14px;color:var(--verified);margin-bottom:18px}
.verified .dot{width:8px;height:8px;border-radius:50%;background:var(--verified);flex:none;box-shadow:none}
.job-meta{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:22px}
.apply-row{display:flex;flex-wrap:wrap;gap:12px;align-items:center;margin:22px 0}
.note{background:var(--panel);border:1px solid var(--line);border-radius:16px;
  padding:18px 20px;font-size:14px;color:var(--muted)}
.note h2{font-size:15px;color:var(--ink);margin-bottom:6px;text-align:left}
.ad{margin:28px 0;padding:18px;border:1px solid var(--line);border-radius:14px;
  background:var(--tint);text-align:center;min-height:90px}
.ad .placeholder{color:var(--faint);font-size:13px}
#cookie{position:fixed;left:16px;right:16px;bottom:16px;max-width:34rem;margin:0 auto;
  background:var(--panel);border:1px solid var(--line);border-radius:14px;padding:14px 16px;
  font-size:13px;color:var(--muted);display:flex;gap:12px;align-items:center;
  box-shadow:0 8px 28px rgba(0,0,0,.14)}
#cookie button{font:inherit;font-size:13px;font-weight:600;padding:8px 14px;flex:none;
  border:1px solid var(--accent2);background:var(--accent2);color:#FFF6F1;border-radius:9px;cursor:pointer}
[hidden]{display:none!important}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px}

footer{border-top:1px solid var(--line);padding:28px 0 44px;color:var(--muted);
  font-size:13.5px;text-align:center;margin-top:8px}
footer a{color:var(--muted);text-decoration:underline}
footer .links{display:flex;gap:18px;justify-content:center;flex-wrap:wrap;margin-bottom:10px}
footer .fine{max-width:70ch;margin:0 auto 10px;color:var(--faint);font-size:12.5px}

/* legal pages */
.legal{max-width:68ch;margin:0 auto;padding:8px 0 24px}
.legal h1.page{text-align:left}
.legal h2{font-size:18px;text-align:left;margin:28px 0 8px}
.legal p,.legal li{color:var(--muted);font-size:15px;line-height:1.65}
.legal ul{padding-left:22px;margin:8px 0}
.legal a{color:var(--ink);text-decoration:underline}
.legal .updated{font-size:13px;color:var(--faint);margin:0 0 22px}

@media (max-width:640px){ .count{margin-left:0;width:100%} }
"""

APPLE_SVG = (
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16.365 1.43c0 1.14-.47 2.28-1.2'
    '3 3.11-.83.9-2.2 1.6-3.32 1.51-.14-1.1.42-2.28 1.16-3.02.83-.85 2.28-1.5 3.39-1.6.01.'
    '33.01.66 0 1zM20.7 17.4c-.57 1.32-1.26 2.63-2.35 3.87-.94 1.06-1.68 1.79-2.9 1.79-1.2'
    '3 0-1.63-.79-3.24-.79-1.63 0-2.06.77-3.23.81-1.18.04-2.04-1.13-2.98-2.19-2.05-2.35-3.6'
    '2-6.63-1.51-9.53.55-1.44 1.53-2.35 2.66-2.37 1.13-.02 2.19.76 2.9.76.68 0 1.98-.94 3.3'
    '4-.8.57.02 2.17.23 3.2 1.73-2.81 1.72-2.36 5.75.32 6.94z"/></svg>'
)

# Inline app-icon mark (roll-call tick) — keeps the landing page at zero external requests.
ICON_SVG = (
    '<svg class="appicon" viewBox="0 0 1024 1024" role="img" aria-label="Rolecall">'
    '<rect width="1024" height="1024" rx="230" fill="#F3EEE3"/>'
    '<path d="M218 520 L292 594 L686 208" fill="none" stroke="#211F1C" '
    'stroke-width="104" stroke-linecap="round" stroke-linejoin="round"/></svg>'
)


def shell(*, title, description, canonical, body, base_url, is_job=False, landing=False, extra_head=""):
    year = datetime.now(timezone.utc).year
    topbar = "" if landing else """<header class="topbar"><div class="wrap">
  <a class="brand" href="{base}/">Rolecall</a>
  <nav><a href="{base}/board/">Board</a><a href="{base}/#how">How it works</a></nav>
</div></header>""".format(base=esc(base_url))
    inner = body if landing else '<main class="wrap">{}</main>'.format(body)
    cookie_line = ("This page carries one ad slot; if ads are enabled the provider may set cookies."
                   if is_job else "No account, no analytics, no cookies on this page.")
    return """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<link rel="canonical" href="{canonical}">
<meta name="robots" content="index,follow">
<meta property="og:type" content="website">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{description}">
<meta property="og:url" content="{canonical}">
<meta name="theme-color" content="#F6F3EC" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#17150F" media="(prefers-color-scheme: dark)">
<style>{css}</style>
{extra_head}
</head>
<body>
{topbar}
{inner}
<footer><div class="wrap">
  <div class="links">
    <a href="{base}/">Home</a>
    <a href="{base}/board/">Board</a>
    <a href="{base}/privacy/">Privacy</a>
    <a href="{base}/terms/">Terms</a>
    <a href="mailto:{sponsor}?subject=Sponsored%20listing%20on%20Rolecall">Sponsor a role</a>
  </div>
  <div class="fine">Company names identify the employers whose public career feeds Rolecall reads.
  Rolecall is not affiliated with, endorsed by, or sponsored by any company named.
  {cookie_line}</div>
  <div>&copy; {year} AvaResearch LLC &middot; Rolecall &middot; Product-design jobs, straight from the source.</div>
</div></footer>
</body>
</html>
""".format(
        title=esc(title), description=esc(description), canonical=esc(canonical),
        css=CSS, extra_head=extra_head, topbar=topbar, inner=inner,
        base=esc(base_url), sponsor=esc(SPONSOR_CONTACT), year=year, cookie_line=cookie_line,
    )


# --------------------------------------------------------------------------
# Pages
# --------------------------------------------------------------------------

def render_landing(data, base_url):
    n = data.get("count", len(data.get("roles", [])))
    base = esc(base_url)
    live = APP_STORE_URL and not APP_STORE_URL.startswith("#")
    if live:
        hero_cta = '<a class="cta" href="{}">{}<span>Download on the App&nbsp;Store</span></a>'.format(
            esc(APP_STORE_URL), APPLE_SVG)
        hero_pill = '<span class="pill"><span class="dot"></span>{} roles live right now</span>'.format(n)
    else:
        hero_cta = '<a class="cta" href="{}/board/">Browse the board &rarr;</a>'.format(base)
        hero_pill = '<span class="pill"><span class="dot"></span>Coming soon to the App Store</span>'
    app_cta = hero_cta
    body = """
<header class="hero"><div class="wrap">
  {icon}
  <h1>Rolecall</h1>
  <p class="tagline">Every design job, verified live.</p>
  <p class="sub">A designer&rsquo;s trustworthy shortcut to every live product-design role at a
  real tech company. Rolecall reads each company&rsquo;s own applicant-tracking feed and
  checks every posting is still open before you see it &mdash; no ghost jobs, no dead links,
  no login.</p>
  {hero_cta}
  <p class="ctanote">The iOS app is ad-free and tracker-free &mdash; App Privacy &ldquo;Data Not Collected.&rdquo;</p>
  {hero_pill}
  <p class="price">{n} roles live now &middot; free to search &middot; no account &middot; iPhone</p>
</div></header>

<section id="why">
  <div class="wrap">
    <h2>Not another job aggregator</h2>
    <p class="lead">Most boards scrape LinkedIn and Indeed, keep the stale posts, and bury the
    real ones. Rolecall does the opposite &mdash; one vertical, from the source, kept honest.</p>
    <div class="grid">
      <div class="card"><div class="ic">&#10003;</div>
        <h3>Straight from the company</h3>
        <p>Every role is pulled from the employer&rsquo;s public ATS feed &mdash; Greenhouse,
        Lever, Ashby, Workday. No LinkedIn, no Indeed, no reposts, no recruiter middle-layer.</p></div>
      <div class="card"><div class="ic">&#9201;</div>
        <h3>Verified still-live</h3>
        <p>Before a role reaches you, Rolecall confirms it still resolves to a real open
        requisition. When it closes, it disappears on the next refresh. Every card shows
        when it was last checked.</p></div>
      <div class="card"><div class="ic">&#9788;</div>
        <h3>One vertical, done properly</h3>
        <p>Product, UX, UI, visual and brand design; design systems and design engineering;
        UX research. Not a catch-all board &mdash; the roles designers actually want, and
        nothing else in the way.</p></div>
      <div class="card"><div class="ic">&#128274;</div>
        <h3>Nothing to sign into</h3>
        <p>No account, no email, no analytics SDK, no ad network in the app. Saved roles and
        your application tracker live only on your device.</p></div>
      <div class="card"><div class="ic">&#128241;</div>
        <h3>Built for the eye that judges it</h3>
        <p>A calm, typographic app made for designers &mdash; and for the Apple editors who
        share the same taste. Widget, Siri, dark mode, Dynamic Type, VoiceOver from day one.</p></div>
      <div class="card"><div class="ic">&#8599;</div>
        <h3>One tap to the real page</h3>
        <p>Apply opens the company&rsquo;s own application page. Rolecall never re-hosts the
        form, adds a tracking redirect, or asks you to sign in first.</p></div>
    </div>
  </div>
</section>

<section class="tight" id="how">
  <div class="wrap">
    <h2>How it works</h2>
    <p class="lead">The engine runs so the app can stay simple.</p>
    <div class="steps">
      <div class="step"><p><b>Read the source.</b> Rolecall ingests each company&rsquo;s public
      ATS feed on a schedule &mdash; the same data the employer publishes on its own careers
      page, nothing scraped from a job board.</p></div>
      <div class="step"><p><b>Keep only design.</b> A rules-first classifier keeps product,
      UX, UI, visual and brand design, design systems, design engineering and UX research
      &mdash; and drops everything else.</p></div>
      <div class="step"><p><b>Verify it&rsquo;s live.</b> Each posting is checked that it still
      opens to a real requisition. A role that has closed drops off &mdash; usually within
      a few hours.</p></div>
      <div class="step"><p><b>Hand it over.</b> The app shows what&rsquo;s fresh, you tap
      through to the company&rsquo;s own page, and &mdash; if you want &mdash; track the
      application by hand through to an offer.</p></div>
    </div>
    <p style="text-align:center"><a href="{base}/board/">Browse every live role &rarr;</a></p>
  </div>
</section>

<section class="tight">
  <div class="wrap">
    <h2>The promise, plainly</h2>
    <p class="lead">Rolecall is the only design job board that can honestly say all of this at once:</p>
    <div class="claim">
      <ul>
        <li>Every listing is <strong>pulled straight from the company&rsquo;s own ATS feed</strong> &mdash; not LinkedIn, not Indeed, not a repost.</li>
        <li>Every listing is <strong>checked still-open</strong> before you see it, and again on every refresh.</li>
        <li>The app has <strong>no account, no analytics, and no ads</strong>, ever.</li>
        <li><strong>Apply goes to the employer&rsquo;s own page</strong> &mdash; no re-hosted form, no redirect, no sign-in wall.</li>
        <li>It covers <strong>one vertical completely</strong> &mdash; US product-design roles &mdash; rather than everything, badly.</li>
      </ul>
    </div>
  </div>
</section>

<section class="tight">
  <div class="wrap">
    <div class="pledge">
      <h2 style="margin-bottom:12px">The honest bit</h2>
      <p style="color:var(--muted);margin:0">Rolecall shows roles that are <strong>live on the
      employer&rsquo;s own site</strong> at the time of the last check. It can&rsquo;t promise
      a role is still open the moment you tap through, and it only covers companies whose
      feeds it reads &mdash; a growing list, not all of them. If a link is ever dead, that&rsquo;s
      a bug: tell us at <a href="mailto:{sponsor}">{sponsor}</a>.</p>
    </div>
    <div class="cta-block" style="margin-top:32px">
      {app_cta}
      <p class="ctanote" style="margin:8px auto 0">{n} roles live now &middot; free to search &middot; no account.</p>
    </div>
  </div>
</section>
""".format(
        icon=ICON_SVG, hero_cta=hero_cta, hero_pill=hero_pill, app_cta=app_cta,
        base=base, n=n, sponsor=esc(SPONSOR_CONTACT),
    )
    return shell(
        title="Rolecall — every design job, verified live",
        description=(
            "A source-direct job board for product-design roles. Every listing pulled "
            "straight from the company's own ATS and verified still-live. No ghost jobs, "
            "no dead links, no login."
        ),
        canonical=base_url + "/",
        body=body,
        base_url=base_url,
        is_job=False,
        landing=True,
    )


def render_board(data, base_url, now):
    roles = data.get("roles", [])
    fams_present = [f for f in FAMILY_ORDER if any(r.get("family") == f for r in roles)]
    fams_present += sorted(
        {r.get("family") for r in roles if r.get("family") not in FAMILY_ORDER and r.get("family")}
    )
    opts = "".join(
        '<option value="{v}">{l}</option>'.format(v=esc(f), l=esc(family_label(f)))
        for f in fams_present
    )

    items = []
    for r in roles:
        slug = r["_slug"]
        remote = r.get("remote")
        remote_attr = "true" if remote is True else "false"
        search_blob = " ".join(
            str(x) for x in (r.get("company"), r.get("title"), r.get("location"), family_label(r.get("family")))
        ).lower()
        loc = r.get("location") or ("Remote" if remote is True else "Location not stated")
        tags = ['<span class="tag">{}</span>'.format(esc(family_label(r.get("family"))))]
        if remote is True:
            tags.append('<span class="tag">Remote</span>')
        items.append(
            """    <li class="role" data-role data-family="{fam}" data-remote="{rem}" data-search="{blob}">
      <a class="role-link" href="{base}/jobs/{slug}.html">
        <div class="co">{co}</div>
        <div class="ti">{ti}</div>
        <div class="mt">{tags}<span>{loc}</span><span>verified {rel}</span></div>
      </a>
    </li>""".format(
                fam=esc(r.get("family") or ""),
                rem=remote_attr,
                blob=esc(search_blob),
                base=esc(base_url),
                slug=esc(slug),
                co=esc(r.get("company") or ""),
                ti=esc(r.get("title") or ""),
                tags="".join(tags),
                loc=esc(loc),
                rel=esc(rel_time(r.get("last_verified") or data.get("generated_utc"), now)),
            )
        )

    body = """
<h1 class="page">The board</h1>
<p class="small">{n} roles live &middot; refreshed {gen} UTC &middot; from company ATS feeds &middot; each checked still-open</p>

<div class="sponsored">
  <span class="spon-label">Sponsored role</span>
  <p>This slot features one employer&rsquo;s open role at the top of the board for a week.
  It is a paid placement and is always labelled. <a href="mailto:{sponsor}?subject=Sponsored%20listing%20on%20Rolecall">Feature your role &rarr;</a>
  <br><em>(No sponsor this week &mdash; slot shown as a stub.)</em></p>
</div>

<form class="toolbar" role="search" onsubmit="return false">
  <input type="search" id="q" placeholder="Search company, title, location&hellip;" aria-label="Search roles">
  <select id="fam" aria-label="Role family">
    <option value="">All families</option>
    {opts}
  </select>
  <label class="chk"><input type="checkbox" id="rem"> Remote only</label>
  <span class="count"><span id="count">{n}</span> shown</span>
</form>

<ul class="roles" id="roles">
{items}
</ul>
<p class="empty" id="empty" hidden>No roles match those filters.</p>

<script>
(function(){{
  var q=document.getElementById('q'), fam=document.getElementById('fam'),
      rem=document.getElementById('rem'), count=document.getElementById('count'),
      empty=document.getElementById('empty');
  var cards=[].slice.call(document.querySelectorAll('[data-role]'));
  function apply(){{
    var t=(q.value||'').toLowerCase().trim(), f=fam.value, r=rem.checked, n=0;
    for(var i=0;i<cards.length;i++){{
      var c=cards[i], ok=true;
      if(f && c.getAttribute('data-family')!==f) ok=false;
      if(ok && r && c.getAttribute('data-remote')!=='true') ok=false;
      if(ok && t && c.getAttribute('data-search').indexOf(t)===-1) ok=false;
      c.hidden=!ok; if(ok) n++;
    }}
    count.textContent=n;
    empty.hidden = n>0;
  }}
  q.addEventListener('input',apply);
  fam.addEventListener('change',apply);
  rem.addEventListener('change',apply);
  apply();
}})();
</script>
""".format(
        n=len(roles),
        gen=esc(iso_date(data.get("generated_utc", now))),
        sponsor=esc(SPONSOR_CONTACT),
        opts=opts,
        items="\n".join(items),
    )
    return shell(
        title="The board — every live product-design role | Rolecall",
        description=(
            "Browse every live product-design, design-engineering, UX-research and "
            "product-management role, pulled straight from company ATS feeds and verified "
            "still-open. Filter by family and remote."
        ),
        canonical=base_url + "/board/",
        body=body,
        base_url=base_url,
        is_job=False,
    )


def render_job(role, data, base_url, now):
    slug = role["_slug"]
    page_url = "{}/jobs/{}.html".format(base_url, slug)
    company = role.get("company") or "the company"
    title = role.get("title") or "Open role"
    ref_ts = role.get("last_verified") or data.get("generated_utc") or now
    posted_ts = role.get("first_seen") or ref_ts
    remote = role.get("remote")
    loc_text = role.get("location") or ("Remote" if remote is True else "Location not stated")

    # ---- JSON-LD JobPosting ------------------------------------------------
    desc_html = (
        "<p>{title} at {company}.</p>"
        "<p>This posting was verified live on {date} directly from {company}&rsquo;s "
        "official applicant-tracking feed. Rolecall lists only roles that are currently "
        "open on the employer&rsquo;s own careers site &mdash; no reposts, no expired "
        "listings, no third-party application forms.</p>"
        "<p>Apply directly on {company}&rsquo;s site using the link on this page.</p>"
    ).format(title=esc(title), company=esc(company), date=iso_date(ref_ts))

    ld = {
        "@context": "https://schema.org/",
        "@type": "JobPosting",
        "title": title,
        "description": desc_html,
        "datePosted": iso_dt(posted_ts),
        "employmentType": employment_type(title),
        "hiringOrganization": {"@type": "Organization", "name": company},
        "directApply": True,
        "url": page_url,
        "identifier": {"@type": "PropertyValue", "name": company, "value": slug},
    }
    places = parse_locations(role.get("location"))
    if places:
        ld["jobLocation"] = places if len(places) > 1 else places[0]
    if remote is True:
        ld["jobLocationType"] = "TELECOMMUTE"
        ld["applicantLocationRequirements"] = {
            "@type": "Country",
            "name": guess_country(role.get("location")) or "United States",
        }
    ld_block = '<script type="application/ld+json">\n{}\n</script>'.format(
        json.dumps(ld, indent=2, ensure_ascii=False)
    )

    # ---- body -----------------------------------------------------------------
    tags = ['<span class="tag">{}</span>'.format(esc(family_label(role.get("family"))))]
    if remote is True:
        tags.append('<span class="tag">Remote</span>')
    tags.append('<span class="tag">{}</span>'.format(esc(loc_text)))

    body = """
<article>
  <div class="job-head">
    <div class="co">{co}</div>
    <h1>{ti}</h1>
    <div class="verified"><span class="dot"></span> verified live &middot; {rel}</div>
    <div class="job-meta">{tags}</div>
  </div>

  <div class="apply-row">
    <a class="btn" href="{url}" rel="nofollow noopener" target="_blank">Apply on {co}&rsquo;s site &rarr;</a>
    <a class="btn ghost" href="{base}/board/">Back to the board</a>
  </div>

  <p class="small">Rolecall sends you straight to {co}&rsquo;s own application page. We
  don&rsquo;t re-host the form, add a redirect, or ask you to sign in.</p>

  <!-- ADSENSE SLOT: single unit, job pages only -->
  <!--
    Rolecall monetization rule (Fellows' ruling): AdSense appears ONLY on job-detail
    pages, exactly one unit, and NEVER on the landing page or the board index.
    To go live: paste the real publisher id into ADSENSE_CLIENT in web/build.py
    (currently "{ad_client}") and uncomment the three lines below.
  -->
  <aside class="ad" aria-label="Advertisement">
    <span class="ad-label">Advertisement</span>
    <div class="placeholder">AdSense slot &mdash; inactive until a real publisher ID is set</div>
    <!-- <script async src="https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client={ad_client}" crossorigin="anonymous"></script> -->
    <!-- <ins class="adsbygoogle" style="display:block" data-ad-client="{ad_client}" data-ad-slot="{ad_slot}" data-ad-format="auto" data-full-width-responsive="true"></ins> -->
    <!-- <script>(adsbygoogle = window.adsbygoogle || []).push({{}});</script> -->
  </aside>

  <div class="note">
    <h2>Why you can trust this listing</h2>
    <p>Pulled from {co}&rsquo;s public ATS feed and last confirmed open on {date} (UTC).
    If {co} closes this role, it drops off Rolecall on the next refresh &mdash; usually
    within a few hours. If this link is dead, it&rsquo;s a bug: tell us at
    <a href="mailto:{sponsor}">{sponsor}</a>.</p>
  </div>
</article>

<div id="cookie" hidden role="dialog" aria-label="Cookie notice">
  <span>This page shows one ad. If ads are enabled, the ad provider may set cookies.
  The rest of Rolecall &mdash; the app, the landing page, the board &mdash; sets none.
  <a href="{base}/#how">More</a>.</span>
  <button type="button" id="cookie-ok">OK</button>
</div>
<script>
(function(){{
  var b=document.getElementById('cookie'), K='rc_cookie_ack';
  try{{ if(localStorage.getItem(K)) return; }}catch(e){{}}
  b.hidden=false;
  document.getElementById('cookie-ok').addEventListener('click',function(){{
    b.hidden=true; try{{ localStorage.setItem(K,'1'); }}catch(e){{}}
  }});
}})();
</script>
""".format(
        co=esc(company),
        ti=esc(title),
        rel=esc(rel_time(ref_ts, now)),
        tags="".join(tags),
        url=esc(role.get("url") or "#"),
        base=esc(base_url),
        ad_client=esc(ADSENSE_CLIENT),
        ad_slot=esc(ADSENSE_SLOT),
        date=esc(iso_date(ref_ts)),
        sponsor=esc(SPONSOR_CONTACT),
    )

    meta_desc = "{ti} at {co}. Verified live on {date}, straight from {co}'s own careers feed. Apply directly — no login, no redirect.".format(
        ti=title, co=company, date=iso_date(ref_ts)
    )
    return shell(
        title="{} — {} | Rolecall".format(title, company),
        description=meta_desc[:300],
        canonical=page_url,
        body=body,
        base_url=base_url,
        is_job=True,
        extra_head=ld_block,
    )


def render_sitemap(data, base_url, now):
    lastmod = iso_date(data.get("generated_utc", now))
    urls = [base_url + "/", base_url + "/board/", base_url + "/privacy/", base_url + "/terms/"]
    urls += ["{}/jobs/{}.html".format(base_url, r["_slug"]) for r in data.get("roles", [])]
    entries = "\n".join(
        "  <url><loc>{}</loc><lastmod>{}</lastmod></url>".format(esc(u), lastmod) for u in urls
    )
    return '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n{}\n</urlset>\n'.format(
        entries
    )


def render_robots(base_url):
    return "User-agent: *\nAllow: /\n\nSitemap: {}/sitemap.xml\n".format(base_url)


def render_404(base_url):
    body = """
<section class="tight" style="padding-top:64px;text-align:center">
  <div class="wrap">
    <h1 class="page">Not here</h1>
    <p class="lead">That page moved, or the role closed and dropped off the board.</p>
    <p class="cta-block"><a class="btn" href="{base}/board/">Browse every live role &rarr;</a></p>
  </div>
</section>
""".format(base=esc(base_url))
    return shell(
        title="Not found — Rolecall",
        description="That page isn't here.",
        canonical=base_url + "/404.html",
        body=body,
        base_url=base_url,
        is_job=False,
        landing=False,
    )


LEGAL_UPDATED = "September 8, 2026"


def render_privacy(base_url):
    body = """
<div class="legal">
  <h1 class="page">Privacy Policy</h1>
  <p class="updated">Last updated {updated}</p>

  <p>Rolecall is a job board for product-design roles, published by AvaResearch LLC
  (&ldquo;we&rdquo;). This policy covers the Rolecall iOS app and this website. The short
  version: we don&rsquo;t have accounts, we don&rsquo;t run analytics or trackers, and we
  don&rsquo;t sell data &mdash; because we don&rsquo;t collect it.</p>

  <h2>The app</h2>
  <ul>
    <li><strong>No account, no sign-in.</strong> The app never asks for your name, email,
    or any identifier.</li>
    <li><strong>Everything stays on your device.</strong> The roles you save, the
    applications you track, your notes, reminders, saved searches, and settings are stored
    only on your iPhone. We have no server that can see them.</li>
    <li><strong>No analytics or tracking SDKs.</strong> The app contains no third-party
    analytics, advertising, or attribution code. Apple&rsquo;s App Privacy label for
    Rolecall is &ldquo;Data Not Collected.&rdquo;</li>
    <li><strong>Network use.</strong> The app downloads one file &mdash; the public job
    board &mdash; from our hosting provider (Cloudflare). That request includes your IP
    address and a standard user-agent string, which Cloudflare processes to deliver the
    file and may log transiently for security and abuse prevention. We do not receive or
    retain it.</li>
    <li><strong>Notifications.</strong> If you turn on a digest or a follow-up reminder,
    the app schedules a local notification on your device. Nothing is sent to us or to a
    push server.</li>
    <li><strong>Rolecall Plus.</strong> If you subscribe, the purchase is handled entirely
    by Apple. We never see your payment details, and there is no account tied to the
    subscription &mdash; your device checks entitlement directly with the App Store.</li>
  </ul>

  <h2>This website</h2>
  <ul>
    <li>The landing page and the job board set no cookies and run no analytics.</li>
    <li>Individual job-detail pages reserve one advertising slot. It is currently
    inactive. If we ever enable it, the ad provider (Google AdSense) may set cookies on
    those pages only; this policy will be updated before that happens, and the pages carry
    a notice.</li>
    <li>Our host, Cloudflare, processes server logs (including IP addresses) to serve the
    site and protect it from abuse, under
    <a href="https://www.cloudflare.com/privacypolicy/" rel="nofollow noopener" target="_blank">Cloudflare&rsquo;s privacy policy</a>.</li>
  </ul>

  <h2>Children</h2>
  <p>Rolecall is intended for adults in the job market and is not directed to children
  under 13.</p>

  <h2>Your rights</h2>
  <p>Because we hold no personal data about you, there is nothing for us to export or
  delete on request. To remove everything the app stores, use Settings &rsaquo; Clear all
  my data, or delete the app.</p>

  <h2>Changes</h2>
  <p>If this policy changes, we&rsquo;ll update the date above and, for material changes,
  note it on the site.</p>

  <h2>Contact</h2>
  <p>Questions: <a href="mailto:{contact}">{contact}</a>.</p>
</div>
""".format(updated=LEGAL_UPDATED, contact=esc(SUPPORT_CONTACT))
    return shell(
        title="Privacy Policy — Rolecall",
        description="Rolecall keeps no account and collects no personal data. The full privacy policy.",
        canonical=base_url + "/privacy/",
        body=body,
        base_url=base_url,
        is_job=False,
        landing=False,
    )


def render_terms(base_url):
    body = """
<div class="legal">
  <h1 class="page">Terms of Use</h1>
  <p class="updated">Last updated {updated}</p>

  <p>These terms cover your use of the Rolecall iOS app and this website, published by
  AvaResearch LLC. By using Rolecall you agree to them.</p>

  <h2>What Rolecall is</h2>
  <p>Rolecall aggregates product-design job postings from companies&rsquo; own public
  applicant-tracking feeds and links you to each company&rsquo;s official application
  page. We are not a recruiter or an employer, we are not affiliated with the companies
  listed, and we are not party to any application or hiring decision. Company names are
  used only to identify the employer whose public feed a listing comes from.</p>

  <h2>The listings</h2>
  <p>We work to show only roles that are currently open and to drop them promptly once
  they close, but we don&rsquo;t guarantee that every listing is accurate, current, or
  still available. Always confirm details on the company&rsquo;s own page. If you find a
  dead or wrong link, tell us at <a href="mailto:{contact}">{contact}</a>.</p>

  <h2>Acceptable use</h2>
  <ul>
    <li>Rolecall is for personal use in your own job search.</li>
    <li>Don&rsquo;t scrape, resell, or redistribute the board, and don&rsquo;t try to
    disrupt or overload the service.</li>
  </ul>

  <h2>Rolecall Plus</h2>
  <ul>
    <li>The job board &mdash; searching, viewing roles, saving them, and marking them
    applied &mdash; is free and always will be.</li>
    <li>Rolecall Plus is an optional auto-renewing subscription that unlocks convenience
    features (saved-search alerts, unlimited saved searches, advanced filters, follow-up
    reminders, and private notes). Pricing is shown in the app before you buy.</li>
    <li>Payment is charged to your Apple Account at confirmation. The subscription renews
    automatically for the same period and price unless you cancel at least 24 hours before
    the current period ends. A free trial, if offered, converts to a paid subscription on
    the same terms unless cancelled at least 24 hours before it ends; any unused portion of
    a trial is forfeited when you buy a subscription.</li>
    <li>Manage or cancel anytime in Settings &rsaquo; Apple Account &rsaquo; Subscriptions
    on your device. Purchases, refunds, and billing are handled by Apple under the
    <a href="https://www.apple.com/legal/internet-services/itunes/dev/stdeula/" rel="nofollow noopener" target="_blank">Apple Media Services Terms</a> (the standard EULA), which
    also govern your licence to use the app.</li>
  </ul>

  <h2>No warranty; limitation of liability</h2>
  <p>Rolecall is provided &ldquo;as is,&rdquo; without warranties of any kind. To the
  fullest extent permitted by law, AvaResearch LLC is not liable for any indirect,
  incidental, or consequential damages arising from your use of Rolecall, and our total
  liability for any claim relating to the service is limited to the amount you paid us for
  it in the 12 months before the claim.</p>

  <h2>Changes</h2>
  <p>We may update these terms; we&rsquo;ll change the date above and, for material
  changes, note it on the site. Continued use after a change means you accept it.</p>

  <h2>Contact</h2>
  <p><a href="mailto:{contact}">{contact}</a></p>
</div>
""".format(updated=LEGAL_UPDATED, contact=esc(SUPPORT_CONTACT))
    return shell(
        title="Terms of Use — Rolecall",
        description="The terms for using Rolecall and Rolecall Plus.",
        canonical=base_url + "/terms/",
        body=body,
        base_url=base_url,
        is_job=False,
        landing=False,
    )


HEADERS_FILE = """# Cloudflare Pages / Netlify header rules.
# The app's feed is served from this same deploy; it must be CORS-open and
# cached briefly so the iOS app and the web board can both read it.

/board.json
  Access-Control-Allow-Origin: *
  Cache-Control: public, max-age=300, s-maxage=300
  Content-Type: application/json; charset=utf-8

# P0-7: the detached signature and the v2 envelope MUST share board.json's cache policy,
# or the edge can expire them at different times and the app sees a board/sig skew.
/board.json.sig
  Access-Control-Allow-Origin: *
  Cache-Control: public, max-age=300, s-maxage=300
  Content-Type: text/plain; charset=utf-8

/board.v2.json
  Access-Control-Allow-Origin: *
  Cache-Control: public, max-age=300, s-maxage=300
  Content-Type: application/json; charset=utf-8

/jobs/*
  Cache-Control: public, max-age=900, s-maxage=3600

/*.html
  Cache-Control: public, max-age=600
"""


# --------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------

def assign_slugs(roles):
    seen = {}
    for r in roles:
        base = "{}-{}".format(slugify(r.get("company", ""), 32), slugify(r.get("title", ""), 70))
        slug = base
        i = 2
        while slug in seen:
            slug = "{}-{}".format(base, i)
            i += 1
        seen[slug] = True
        r["_slug"] = slug


def build(base_url: str) -> int:
    if not BOARD_PATH.exists():
        print("error: {} not found — run `python3 -m engine export` first".format(BOARD_PATH))
        return 1
    base_url = base_url.rstrip("/")
    data = json.loads(BOARD_PATH.read_text())
    all_roles = data.get("roles", [])
    roles = [r for r in all_roles if in_scope(r)]
    data["roles"] = roles
    data["count"] = len(roles)
    now = time.time()
    assign_slugs(roles)
    print("  in scope: {} of {} roles (design vertical, US + remote)".format(
        len(roles), len(all_roles)))

    if DIST.exists():
        shutil.rmtree(DIST)
    (DIST / "board").mkdir(parents=True)
    (DIST / "jobs").mkdir(parents=True)
    (DIST / "privacy").mkdir(parents=True)
    (DIST / "terms").mkdir(parents=True)

    (DIST / "index.html").write_text(render_landing(data, base_url))
    (DIST / "board" / "index.html").write_text(render_board(data, base_url, now))
    for r in roles:
        (DIST / "jobs" / (r["_slug"] + ".html")).write_text(render_job(r, data, base_url, now))

    (DIST / "privacy" / "index.html").write_text(render_privacy(base_url))
    (DIST / "terms" / "index.html").write_text(render_terms(base_url))

    (DIST / "sitemap.xml").write_text(render_sitemap(data, base_url, now))
    (DIST / "robots.txt").write_text(render_robots(base_url))
    (DIST / "404.html").write_text(render_404(base_url))  # Pages serves this with a real 404 status
    (DIST / "_headers").write_text(HEADERS_FILE)  # Cloudflare Pages applies these header rules
    shutil.copyfile(BOARD_PATH, DIST / "board.json")
    sig = BOARD_PATH.with_suffix(".json.sig")
    if sig.exists():
        shutil.copyfile(sig, DIST / "board.json.sig")   # detached Ed25519 signature for the app
    v2 = BOARD_PATH.with_name("board.v2.json")
    if v2.exists():
        # P0-7: board + signature as one artifact — the app fetches this single URL so the
        # edge can't serve a new board against a stale cached signature. Legacy two-file
        # layout above stays for one release.
        shutil.copyfile(v2, DIST / "board.v2.json")

    print("built {} pages -> {}".format(2 + len(roles), DIST))
    print("  landing : index.html")
    print("  board   : board/index.html")
    print("  jobs    : jobs/*.html  ({} pages, matches board.json count={})".format(
        len(roles), data.get("count")))
    print("  legal   : privacy/index.html, terms/index.html")
    print("  extras  : sitemap.xml, robots.txt, _headers, board.json")
    print("  base URL: {}".format(base_url))
    return 0


def main(argv) -> int:
    ap = argparse.ArgumentParser(prog="python3 -m web build")
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL, help="site origin (default %(default)s)")
    ns = ap.parse_args(argv)
    return build(ns.base_url)
