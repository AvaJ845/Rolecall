# Rolecall — ASO Playbook

Source: The $50K/Month ASO Playbook. A compounding asset, not a launch sprint:
**rank for terms people type → convert the tap → compound with reviews.** Skipping
any stage breaks the flywheel.

Paste-ready Name / Subtitle / Keywords / Description live in [`METADATA.md`](METADATA.md).

---

## ① Discovery — get found

- [x] **App Store Name** (keyword-first): `Design Jobs - Rolecall` (22/30)
- [x] **Subtitle** (new secondary keywords): `Verified UX & product roles` (27/30)
- [ ] **Keyword field** (App Store Connect): `career,hiring,ui,designer,remote,startup,board,openings,tech,researcher,writer,engineer` — **pad to fill 100 chars** (add e.g. `,hybrid`)
- [x] Naming Council run — **Approve** (see `METADATA.md` for the table)
- [x] Deliberate exclusions recorded (`graphic`, `salary`, ATS brands, competitor names)
- [ ] After launch: track rank monthly for `design jobs`, `ux jobs`, `remote design jobs`; rotate the weakest hidden keyword each update

## ② Conversion — win the tap

3–5 second decision window. Screenshots + icon carry it. Lead with the payoff, one
idea per frame, real captured UI, big legible captions.

### Screenshot set — target order

| # | Screen | Caption (headline / subline · terracotta accent) | Status |
|---|---|---|---|
| 1 | **Board** — "All N checked live" badge visible | *Every design job,\nverified live.* / Straight from the company. No ghost jobs, no dead links. · **verified live.** | ✅ hero |
| 2 | **Role detail** — the verified-live proof card | *Rechecked before\nyou ever see it.* / Rolecall opens the posting and confirms the role is really there. · **Rechecked** | ✅ reshot — opened from Saved list, `crop_bottom` past the empty zone, shot vertically centred |
| 3 | **Applications** — funnel from screen to offer | *Track every application\nthrough to the offer.* / Recruiter screen, hiring manager, final round, offer — one place. · **offer.** | ✅ reseeded — Figma/Linear/Notion/Stripe/Ramp/Duolingo/Airbnb, varied monograms, no competitor |
| 4 | **Filter sheet** — discipline scoping | *Your discipline.\nNothing else.* / Product, UX, brand, design systems, research. US and remote. · **Nothing else.** | ✅ good |
| 5 | **Icon variants** — Classic / Midnight / Mono | *Made for the people\nwho'll judge it hardest.* / Three icons, dark mode, Dynamic Type, VoiceOver — all first-pass. · **hardest.** | ✅ added — composited in `frame.py` from the shipped 1024 PNGs |
| 6 | **Privacy** — "Data Not Collected" beat | *No account.\nNo trackers. Ever.* / Your whole search stays on your device. Nothing is sent anywhere. · **Ever.** | ✅ reshot — scrolls to the bottom; crop opens on the Job-search card + Privacy section |

Final order is fixed: 01 board → 02 verified-detail → 03 applications → 04 filter → 05 icons → 06 privacy.
iPad set is 01–05 (privacy is iPhone-only — Settings on iPad is a small centred form-sheet that
does not read as a trust beat). Pipeline: `ios/AppStore/capture.sh` (clean 9:41 status bar) → `frame.py`.

> **Headline font gotcha:** `/System/Library/Fonts/NewYork.ttf` renders a hyphen (U+002D, and
> U+2010/U+2011) as a blank — an en dash renders, a hyphen does not. Keep headline copy
> hyphen-free ("Rechecked", not "Re-checked"). Sublines use SFNS and are fine.

### Fellows craft review — 2026-09-09

**Genuinely good:** editorial serif headlines (NewYork Bold), warm-paper palette
(`#F6F3EC` / `#2C2823` / terracotta `#AA5C4A`), frameless device shots on paper —
calm, distinctive, exactly the calm-privacy-first aesthetic Apple editorial
rewards. Real UI, benefit-led captions, one idea per frame.

**Fixed (branch `appstore-screenshots-v2`, 2026-09-09):**
1. **02 (role detail):** ~500px dead whitespace — resolved. The detail is opened from the
   Saved list (so the role is always a curated non-competitor), `frame.py` `crop_bottom`
   ends the shot just below the source note, and short shots are vertically centred in the
   paper so the margin reads as deliberate. No app UI change was needed.
2. **03 (applications):** `UITestSupport` now seeds a hand-picked, varied, non-competitor
   set (`curatedCompanies`) matched to real board postings, with an explicit
   `competitorCompanies` exclusion set (LinkedIn, Indeed, Dribbble, Wellfound, AngelList,
   Glassdoor, Otta, …). Monograms are now F/L/N/S/R/D/A; the funnel reads applied →
   recruiter screen → hiring manager → interviewing → final round → offer.
3. **06 (privacy):** the test scrolls to the bottom of Settings (a fixed rest position);
   `frame.py` crops to the Job-search card so the frame opens on a section boundary with
   the Privacy card as the hero. No floating pill, no clipped header.
4. **iPad set:** `capture.sh` applies `simctl status_bar override` (clean 9:41); the
   preset crops the status bar out and a small `crop_bottom_default` + larger corner
   radius removes the display's rounded-corner arc at the source instead of cropping
   around it.
5. **Headline accents:** every headline now accents exactly one payoff phrase in
   terracotta (see the table above).
6. **Caption tightening:** 02 is now "Rechecked before / you ever see it." ("Rechecked",
   not "Re-checked" — the NewYork headline font drops hyphens; see the gotcha above).

- [x] **Icon** — Classic / Midnight / Mono ship; legible at Home-Screen size
- [x] Fix screenshots 2, 3, 6 + iPad artifact per the review above
- [x] Add the icon-variants frame (#5)
- [x] Regenerate all sets: 6.9″ (1320×2868), 6.5″ (1242×2688), 13″ iPad (2048×2732 — 01–05)
- [ ] (Optional) 15–20s App Preview — one real "open a role → verified live → apply" loop
- [ ] Post-launch product-page A/B test: hero screenshot order first

## ③ Momentum — compound with reviews

Apple factors conversion **and** ratings into rank — this closes the loop back to ①.

- [ ] **Review prompt at the happy moment:** fire the native prompt after the user
  marks their **3rd application** as advanced a stage (a real search-is-working
  signal) — once per app version, never at launch/onboarding/after an error
- [ ] **Reply loop:** respond to every review; turn a 1★ into a 5★ by resolving the
  actual complaint
- [ ] **Signature hack:** end support emails with "If Rolecall's saved you from a
  ghost job, a review really helps."
- [ ] **Roadmap signal:** ~20 reviews asking for the same thing → build it, say so in a reply
- [ ] Themed pitch windows for editorial: New Year career features (January),
  graduation (May–June), "Apps with Great Design" / "Tools for Creatives" roundups
