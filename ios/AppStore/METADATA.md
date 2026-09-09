# App Store — Rolecall

Paste-ready. Per the ASO playbook: Apple indexes **App Name + Subtitle + Keywords
field as one string** — every word spent once, never repeated across the three.

## Identity

| Field | Value | Chars |
|---|---|---|
| **App Store Name** (≤30) | `Design Jobs - Rolecall` | 22 |
| **Home Screen name** (`CFBundleDisplayName`) | `Rolecall` | — |
| **Subtitle** (≤30) | `Verified UX & product roles` | 27 |
| **Bundle ID** | `com.avaresearch.rolecall` | — |
| **Primary category** | Business · **Secondary:** Productivity | — |
| **Age rating** | 4+ | — |
| **Price** | Free. Optional **Rolecall Plus** subscription (group `Rolecall Plus`, 7-day free trial). | — |

**Why the Name is keyword-first:** as an unknown indie with no ad budget, the
Name field is the heaviest-weighted slot — it can't be spent on the brand the way
Duolingo can. `Design Jobs` is the exact phrase the target user types; the brand
rides second. The device/Home Screen name stays `Rolecall` (same pattern as
"Habit Tracker - Habit Kit").

## Keywords (≤100, App Store Connect backend field)

```
career,hiring,ui,designer,remote,startup,board,openings,tech,researcher,writer,engineer
```
*(85 chars — room for one more; comma-joined, no spaces, singular, no word repeated from Name/Subtitle, no competitor names.)*

**Combinations harvested** (Name + Subtitle + Keywords indexed together):
`design jobs` · `ux jobs` · `product design jobs` · `ux design jobs` · `design career`
· `design hiring` · `ui jobs` · `ui design` · `designer jobs` · `remote design jobs`
· `remote ux jobs` · `startup design jobs` · `design job board` · `design openings`
· `tech design jobs` · `ux researcher jobs` · `ux writer jobs` · `design engineer jobs`
· `verified jobs` · `verified roles`

**Deliberately excluded:**
- `graphic` — the board carries product/UX/design-systems/design-engineering/research only; "graphic design jobs" seekers would tap, find nothing, and bounce (conversion + honesty-North-Star hit).
- `salary`, `pay` — the app shows no compensation data; a false promise on the listing.
- `resume`, `cv`, `portfolio builder` — not features.
- ATS brand names (`greenhouse`, `lever`, `ashby`, `workday`) — App Review risk trading on third-party marks, and not how designers actually search.
- Competitor app/site names (`linkedin`, `indeed`, `dribbble`, `wellfound`, `angellist`, `glassdoor`) — Apple rejects these.

## Promotional Text (≤170, editable without review)
```
Every live product-design role at a real company — pulled straight from their own careers page and re-checked before you see it. No ghost jobs, no dead links, no account.
```
*(≈168 chars)*

## Description (≤4000)
```
Rolecall is a job board for product designers who are done with ghost jobs.

VERIFIED LIVE
Every role is pulled straight from the company's own hiring system — not scraped from LinkedIn or Indeed. Before a listing reaches you, Rolecall opens the posting and confirms the role is still there. When a company closes a req, it leaves Rolecall on the next refresh, usually within a few hours.

YOUR DISCIPLINE, NOTHING ELSE
Product design, UX, UI, design systems, design engineering, and UX research. US and remote. No marketing roles, no "growth designer who also does sales."

TRACK IT THROUGH TO THE OFFER
Save roles, then move each application along its own funnel — recruiter screen, hiring manager, final round, offer — all on your device.

NO ACCOUNT. NO TRACKERS. EVER.
There is no sign-in of any kind. No analytics SDKs, no ad networks, nothing to leak. Your whole search — saved roles, applications, alerts — stays on this device. App Privacy: Data Not Collected.

Every tap lands on the company's own application page. No re-hosted forms, no tracking redirect.

Free to search, always. Optional Rolecall Plus adds saved-search alerts and a wider history.

Privacy Policy: https://rolecalljobs.com/privacy
Terms of Use: https://rolecalljobs.com/terms
```

## URLs
- **Support / Marketing:** https://rolecalljobs.com
- **Privacy Policy:** https://rolecalljobs.com/privacy
- **Terms of Use:** https://rolecalljobs.com/terms

## App Privacy (nutrition label)
**Data Not Collected.** No account, no analytics/tracking SDKs. Network requests
fetch only public company career-page content to verify a role is still open.

## Review notes (paste into App Review)
```
Rolecall is a read-only job board for product-design roles. It aggregates listings from companies' own public applicant-tracking systems (Greenhouse, Lever, Ashby, Workday) and, before showing a role, fetches the public posting to confirm it is still open. There is no account system of any kind and no data collection — App Privacy is "Data Not Collected." Every "Apply" link opens the company's own public application page in Safari; Rolecall hosts no application forms and adds no tracking. Rolecall Plus (auto-renewable subscription) adds saved-search alerts and extended history; it does not gate the core board, which is always free. To reach the paywall: Settings → Rolecall Plus.
```

---

## Naming Council — 2026-09-09

| Fellow | Lean | Key finding |
|---|---|---|
| **Discoverability** | Approve | Name `Design Jobs - Rolecall` (22) — primary keyword first, brand second ✓. Subtitle (27) repeats no Name word; adds verified/ux/product/roles ✓. Keyword field 85/100 — clean (no repeats, singular, no comp names) but **leaves 15 chars on the table**; add one term (e.g. `,hybrid` or `,visa`). `design jobs` on the App Store sits in the Indie Battlefield, not the Trap — no dedicated design-jobs app dominates the store. |
| **Collision** | Approve | No **exact** `Rolecall` (one word) app on the US App Store ([search](https://apps.apple.com/us/search?term=rolecall)). Nearest names are all two-word "Roll Call" utilities in other categories — [Roll Call Attendance](https://apps.apple.com/us/app/roll-call-attendance-app/id1472047580), [Roll Call - The App for Teams](https://apps.apple.com/us/app/roll-call-the-app-for-teams/id6475636979), [RollCall - LMS Attendance](https://apps.apple.com/us/app/rollcall-lms-attendance/id1078450081) — low tap-confusion. **Flag:** [Roll Call News](https://apps.apple.com/us/app/roll-call-news/id433753469) is CQ Roll Call, an established DC political-news brand (rollcall.com); different category + spelling, low legal risk, but the user should know the media brand exists. Category competitor for the keyword: [Design Remote Jobs](https://apps.apple.com/us/app/design-remote-jobs/id6739151388) — remote-only, no live-verification, broader (graphic/3D). Rolecall's differentiator (ATS-direct + live-verified + no-account + product-design-focus) is distinct. |
| **Portfolio** | Approve | Bundle `com.avaresearch.rolecall` matches the AvaResearch main convention (`com.avaresearch.hummingbird`). No internal collision — no other portfolio app is a job board. "Rolecall" one-word is a deliberate distinctive mark, not tied to a trademark-exposed character (no Top Pup split needed). `Design Jobs - Rolecall` / `Verified UX & product roles` — no restricted terms; "verified" is a claim the engine actually backs (live re-check per role), so it's substantiated, not puffery. |

**VERDICT: Approve** — ship `Design Jobs - Rolecall` / `Verified UX & product roles`. One revise: pad the keyword field to use the full 100 characters.
