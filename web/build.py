"""Static site generator for rolecall.io — stdlib only.

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

DEFAULT_BASE_URL = "https://rolecall.io"

# --------------------------------------------------------------------------
# AdSense — paste the real publisher id here, then uncomment the slot markup
# in the job-page template below. This is the ONLY third-party anything on the
# whole site, and it appears on job-detail pages only. Never on the landing
# page, never on the board index.
ADSENSE_CLIENT = "ca-pub-XXXXXXXXXXXXXXXX"
ADSENSE_SLOT = "0000000000"
# --------------------------------------------------------------------------

SPONSOR_CONTACT = "sponsors@rolecall.io"
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
  --bg:#fbfaf8; --fg:#1b1a18; --muted:#6c6862; --faint:#908b83;
  --line:#e7e3db; --card:#ffffff; --card-2:#f4f1ea;
  --accent:#1b1a18; --accent-fg:#fbfaf8; --link:#3350c9;
  --maxw:64rem;
}
@media (prefers-color-scheme:dark){
  :root{
    --bg:#131211; --fg:#ececea; --muted:#a09b93; --faint:#787169;
    --line:#2b2926; --card:#1b1a18; --card-2:#211f1c;
    --accent:#ececea; --accent-fg:#131211; --link:#9db0ff;
  }
}
html{-webkit-text-size-adjust:100%}
body{
  margin:0; background:var(--bg); color:var(--fg);
  font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
  -webkit-font-smoothing:antialiased; text-rendering:optimizeLegibility;
}
.wrap{max-width:var(--maxw); margin:0 auto; padding:0 1.25rem}
a{color:var(--link); text-decoration:none}
a:hover{text-decoration:underline}
h1,h2,h3{line-height:1.25; font-weight:650; letter-spacing:-0.01em; margin:0 0 .5em}
h1{font-size:clamp(1.9rem,4.5vw,2.9rem)}
h2{font-size:clamp(1.3rem,3vw,1.75rem); margin-top:0}
p{margin:0 0 1rem}
hr{border:0; border-top:1px solid var(--line); margin:2.5rem 0}
small,.small{font-size:.8125rem; color:var(--muted)}
header.site{border-bottom:1px solid var(--line)}
header.site .wrap{display:flex; align-items:center; justify-content:space-between; height:3.75rem}
.brand{font-weight:680; letter-spacing:-0.02em; color:var(--fg); font-size:1.05rem}
.brand:hover{text-decoration:none}
nav.site a{color:var(--muted); margin-left:1.25rem; font-size:.9rem}
footer.site{border-top:1px solid var(--line); margin-top:4rem; padding:2rem 0; color:var(--muted); font-size:.85rem}
footer.site .wrap{display:flex; flex-wrap:wrap; gap:.35rem 1.25rem; align-items:baseline}
footer.site a{color:var(--muted)}
.btn{
  display:inline-block; background:var(--accent); color:var(--accent-fg);
  padding:.8rem 1.35rem; border-radius:.6rem; font-weight:600; font-size:.95rem;
  border:1px solid var(--accent);
}
.btn:hover{text-decoration:none; opacity:.9}
.btn.ghost{background:transparent; color:var(--fg); border-color:var(--line)}
.lede{font-size:clamp(1.05rem,2.2vw,1.3rem); color:var(--muted); max-width:40rem}

/* landing */
.hero{padding:clamp(3rem,9vw,6rem) 0 2rem}
.hero .promise{max-width:34rem; margin:1.5rem 0 2rem; font-size:1.05rem}
.cta-row{display:flex; flex-wrap:wrap; gap:.75rem; align-items:center}
.appstore{
  display:inline-flex; align-items:center; gap:.6rem; background:var(--accent);
  color:var(--accent-fg); padding:.7rem 1.15rem; border-radius:.6rem; font-weight:600;
}
.appstore:hover{text-decoration:none; opacity:.9}
.appstore svg{width:1.25rem; height:1.25rem; fill:currentColor}
.steps{display:grid; gap:1.5rem; grid-template-columns:repeat(auto-fit,minmax(15rem,1fr)); margin:1.5rem 0}
.step{background:var(--card); border:1px solid var(--line); border-radius:.75rem; padding:1.25rem}
.step h3{font-size:1rem; margin-bottom:.35rem}
.step p{margin:0; color:var(--muted); font-size:.9rem}
.step .n{font-size:.75rem; color:var(--faint); font-weight:600; letter-spacing:.08em}

/* board */
.toolbar{
  display:flex; flex-wrap:wrap; gap:.75rem; align-items:center;
  padding:1rem 0 1.25rem; border-bottom:1px solid var(--line); margin-bottom:1.25rem;
}
.toolbar input[type=search],.toolbar select{
  font:inherit; font-size:.9rem; padding:.5rem .7rem; border:1px solid var(--line);
  border-radius:.5rem; background:var(--card); color:var(--fg); min-width:0;
}
.toolbar input[type=search]{flex:1 1 12rem}
.toolbar label.chk{display:inline-flex; align-items:center; gap:.4rem; font-size:.9rem; color:var(--muted)}
.count{color:var(--muted); font-size:.85rem; margin-left:auto}
ul.roles{list-style:none; margin:0; padding:0; display:grid; gap:.5rem}
li.role{border:1px solid var(--line); border-radius:.7rem; background:var(--card)}
li.role a.role-link{display:block; padding:1rem 1.15rem; color:var(--fg)}
li.role a.role-link:hover{text-decoration:none; border-color:var(--faint)}
.role .co{font-size:.8rem; color:var(--muted); font-weight:600; letter-spacing:.02em}
.role .ti{font-size:1.02rem; font-weight:600; margin:.15rem 0 .35rem}
.role .mt{font-size:.82rem; color:var(--muted); display:flex; flex-wrap:wrap; gap:.35rem .9rem}
.tag{
  display:inline-block; font-size:.72rem; font-weight:600; letter-spacing:.02em;
  padding:.12rem .5rem; border-radius:1rem; background:var(--card-2); color:var(--muted);
}
.sponsored{
  border:1px dashed var(--faint); border-radius:.7rem; padding:1rem 1.15rem;
  margin-bottom:1rem; background:var(--card-2);
}
.sponsored .spon-label,.ad .ad-label{
  display:inline-block; font-size:.68rem; font-weight:700; letter-spacing:.1em;
  text-transform:uppercase; color:var(--faint); margin-bottom:.35rem;
}
.sponsored p{margin:0; font-size:.9rem; color:var(--muted)}
.empty{padding:3rem 0; text-align:center; color:var(--muted)}

/* job detail */
.job-head{padding:2rem 0 1rem}
.job-head .co{font-size:.9rem; color:var(--muted); font-weight:600}
.job-head h1{font-size:clamp(1.5rem,4vw,2.1rem); margin:.25rem 0 .75rem}
.verified{
  display:inline-flex; align-items:center; gap:.45rem; font-size:.85rem;
  color:var(--muted); margin-bottom:1.25rem;
}
.verified .dot{width:.5rem; height:.5rem; border-radius:50%; background:#2e9c5a; flex:none}
.job-meta{display:flex; flex-wrap:wrap; gap:.5rem; margin-bottom:1.5rem}
.apply-row{display:flex; flex-wrap:wrap; gap:.75rem; align-items:center; margin:1.5rem 0}
.note{background:var(--card); border:1px solid var(--line); border-radius:.75rem; padding:1.1rem 1.25rem; font-size:.9rem; color:var(--muted)}
.note h2{font-size:.95rem; color:var(--fg); margin-bottom:.4rem}
.ad{
  margin:2rem 0; padding:1rem; border:1px solid var(--line); border-radius:.75rem;
  background:var(--card-2); text-align:center; min-height:6rem;
}
.ad .placeholder{color:var(--faint); font-size:.8rem}
#cookie{
  position:fixed; left:1rem; right:1rem; bottom:1rem; max-width:34rem; margin:0 auto;
  background:var(--card); border:1px solid var(--line); border-radius:.75rem;
  padding:.9rem 1rem; font-size:.82rem; color:var(--muted);
  display:flex; gap:.75rem; align-items:center; box-shadow:0 6px 24px rgba(0,0,0,.12);
}
#cookie button{
  font:inherit; font-size:.8rem; font-weight:600; padding:.45rem .9rem; flex:none;
  border:1px solid var(--accent); background:var(--accent); color:var(--accent-fg);
  border-radius:.5rem; cursor:pointer;
}
[hidden]{display:none!important}
:focus-visible{outline:2px solid var(--link); outline-offset:2px}
@media (max-width:34rem){
  .count{margin-left:0; width:100%}
}
"""

APPLE_SVG = (
    '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M16.365 1.43c0 1.14-.47 2.28-1.2'
    '3 3.11-.83.9-2.2 1.6-3.32 1.51-.14-1.1.42-2.28 1.16-3.02.83-.85 2.28-1.5 3.39-1.6.01.'
    '33.01.66 0 1zM20.7 17.4c-.57 1.32-1.26 2.63-2.35 3.87-.94 1.06-1.68 1.79-2.9 1.79-1.2'
    '3 0-1.63-.79-3.24-.79-1.63 0-2.06.77-3.23.81-1.18.04-2.04-1.13-2.98-2.19-2.05-2.35-3.6'
    '2-6.63-1.51-9.53.55-1.44 1.53-2.35 2.66-2.37 1.13-.02 2.19.76 2.9.76.68 0 1.98-.94 3.3'
    '4-.8.57.02 2.17.23 3.2 1.73-2.81 1.72-2.36 5.75.32 6.94z"/></svg>'
)


def shell(*, title, description, canonical, body, base_url, is_job=False, extra_head=""):
    ldj = extra_head
    year = datetime.now(timezone.utc).year
    footer_note = (
        "No account, no analytics, no cookies on this page."
        if not is_job
        else "This page carries one ad unit; see the notice below."
    )
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
<meta name="theme-color" content="#fbfaf8" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#131211" media="(prefers-color-scheme: dark)">
<style>{css}</style>
{ldj}
</head>
<body>
<header class="site"><div class="wrap">
  <a class="brand" href="{base}/">Rolecall</a>
  <nav class="site">
    <a href="{base}/board/">Board</a>
    <a href="{base}/#how">How it works</a>
  </nav>
</div></header>
<main class="wrap">
{body}
</main>
<footer class="site"><div class="wrap">
  <span>&copy; {year} Rolecall</span>
  <a href="{base}/">Home</a>
  <a href="{base}/board/">Board</a>
  <a href="mailto:{sponsor}">Sponsor a role</a>
  <span class="small">{footer_note}</span>
</div></footer>
</body>
</html>
""".format(
        title=esc(title),
        description=esc(description),
        canonical=esc(canonical),
        css=CSS,
        ldj=ldj,
        base=esc(base_url),
        body=body,
        year=year,
        sponsor=esc(SPONSOR_CONTACT),
        footer_note=footer_note,
    )


# --------------------------------------------------------------------------
# Pages
# --------------------------------------------------------------------------

def render_landing(data, base_url):
    n = data.get("count", len(data.get("roles", [])))
    body = """
<section class="hero">
  <h1>Every design job, verified live.</h1>
  <p class="lede">No ghost jobs, no dead links, no login. A designer&rsquo;s trustworthy
  shortcut to every live product-design role at a real tech company.</p>
  <p class="promise">Rolecall pulls roles straight from each company&rsquo;s own
  applicant-tracking feed and checks every one is still open before you see it. When a
  role closes, it disappears on the next refresh. Right now {n} roles are live.</p>
  <div class="cta-row">
    <a class="appstore" href="{app}">{apple}<span>Download on the App&nbsp;Store</span></a>
    <a class="btn ghost" href="{base}/board/">Browse the web board &rarr;</a>
  </div>
  <p class="small" style="margin-top:1rem">The iOS app is ad-free and tracker-free &mdash;
  App Privacy &ldquo;Data Not Collected.&rdquo;</p>
</section>

<hr>

<section id="how">
  <h2>How it works</h2>
  <div class="steps">
    <div class="step"><p class="n">01</p><h3>Straight from the source</h3>
      <p>We read each company&rsquo;s public ATS feed &mdash; Greenhouse, Lever, Ashby,
      Workday. No LinkedIn, no Indeed, no reposts.</p></div>
    <div class="step"><p class="n">02</p><h3>Verified still-live</h3>
      <p>Every posting is checked that it still resolves to a real open requisition.
      Target: under one dead link per 100 opens.</p></div>
    <div class="step"><p class="n">03</p><h3>Fresh within the hour</h3>
      <p>New roles appear within an hour of going up. Closed roles vanish on the next
      ingest. Each card shows when it was last verified.</p></div>
  </div>
  <p><a href="{base}/board/">See every live role &rarr;</a></p>
</section>

<hr>

<section>
  <h2>Built for designers, and their eye</h2>
  <p class="lede">Product, UX, UI, visual and brand designers; design systems and design
  engineers; UX researchers. Product managers as a secondary family. One vertical, done
  properly &mdash; not a catch-all board.</p>
</section>
""".format(
        n=n,
        app=esc(APP_STORE_URL),
        apple=APPLE_SVG,
        base=esc(base_url),
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
<h1>The board</h1>
<p class="small">{n} roles live &middot; refreshed {gen} UTC &middot; straight from company ATS feeds</p>

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
    within the hour. If this link is dead, it&rsquo;s a bug: tell us at
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
    urls = [base_url + "/", base_url + "/board/"]
    urls += ["{}/jobs/{}.html".format(base_url, r["_slug"]) for r in data.get("roles", [])]
    entries = "\n".join(
        "  <url><loc>{}</loc><lastmod>{}</lastmod></url>".format(esc(u), lastmod) for u in urls
    )
    return '<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n{}\n</urlset>\n'.format(
        entries
    )


def render_robots(base_url):
    return "User-agent: *\nAllow: /\n\nSitemap: {}/sitemap.xml\n".format(base_url)


HEADERS_FILE = """# Cloudflare Pages / Netlify header rules.
# The app's feed is served from this same deploy; it must be CORS-open and
# cached briefly so the iOS app and the web board can both read it.

/board.json
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

    (DIST / "index.html").write_text(render_landing(data, base_url))
    (DIST / "board" / "index.html").write_text(render_board(data, base_url, now))
    for r in roles:
        (DIST / "jobs" / (r["_slug"] + ".html")).write_text(render_job(r, data, base_url, now))

    (DIST / "sitemap.xml").write_text(render_sitemap(data, base_url, now))
    (DIST / "robots.txt").write_text(render_robots(base_url))
    (DIST / "_headers").write_text(HEADERS_FILE)  # honoured by Cloudflare/Netlify; ignored by GH Pages
    shutil.copyfile(BOARD_PATH, DIST / "board.json")

    # GitHub Pages: CNAME binds the custom domain; .nojekyll stops Jekyll from
    # dropping files/dirs that begin with "_".
    host = re.sub(r"^https?://", "", base_url).split("/")[0]
    if host and "localhost" not in host and not host.startswith("staging."):
        (DIST / "CNAME").write_text(host + "\n")
    (DIST / ".nojekyll").write_text("")

    print("built {} pages -> {}".format(2 + len(roles), DIST))
    print("  landing : index.html")
    print("  board   : board/index.html")
    print("  jobs    : jobs/*.html  ({} pages, matches board.json count={})".format(
        len(roles), data.get("count")))
    print("  extras  : sitemap.xml, robots.txt, _headers, board.json")
    print("  base URL: {}".format(base_url))
    return 0


def main(argv) -> int:
    ap = argparse.ArgumentParser(prog="python3 -m web build")
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL, help="site origin (default %(default)s)")
    ns = ap.parse_args(argv)
    return build(ns.base_url)
