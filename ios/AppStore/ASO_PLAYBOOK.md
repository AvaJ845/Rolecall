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

| # | Screen | Caption (headline / subline) | Status |
|---|---|---|---|
| 1 | **Board** — "All N checked live" badge visible | *Every design job,\nverified live.* / Straight from the company. No ghost jobs, no dead links. | ✅ good |
| 2 | **Role detail** — the verified-live proof card | *Re-checked before\nyou ever see it.* / Rolecall opens the posting and confirms the role is really there. | ⚠️ **dead whitespace in shot** |
| 3 | **Applications** — funnel from screen to offer | *Track every application\nthrough to the offer.* / Recruiter screen, hiring manager, final round, offer — one place. | ⚠️ **all-"A" monograms, AngelList shown** |
| 4 | **Filter sheet** — discipline scoping | *Your discipline.\nNothing else.* / Product, UX, design systems, research. US and remote. | ✅ good |
| 5 | **Icon variants** — Classic / Midnight / Mono | *Made for the people\nwho'll judge it hardest.* / Three icons, dark mode, Dynamic Type, VoiceOver — first-pass. | ➕ **add (design-craft signal)** |
| 6 | **Privacy** — "Data Not Collected" beat | *No account.\nNo trackers. Ever.* / Your whole search stays on your device. Nothing is sent anywhere. | ⚠️ **top crop clips header** |

### Fellows craft review — 2026-09-09

**Genuinely good:** editorial serif headlines (NewYork Bold), warm-paper palette
(`#F6F3EC` / `#2C2823` / terracotta `#AA5C4A`), frameless device shots on paper —
calm, distinctive, exactly the calm-privacy-first aesthetic Apple editorial
rewards. Real UI, benefit-led captions, one idea per frame.

**Fix before submission:**
1. **02 (role detail):** ~500px dead whitespace mid-shot — the detail view's short
   content + bottom-pinned Apply button. Fix at the source: seed a longer role, or
   capture the detail as a partial-height card over the board, or tighten the crop.
2. **03 (applications):** the seed sorts companies alphabetically and takes the
   first 7 → every application is an A-company → every monogram renders "A" (reads
   like a bug), and **AngelList (a competitor) is shown prominently** (App Review +
   optics risk). Fix `UITestSupport` to seed a curated set of varied, recognizable,
   **non-competitor** design employers (Figma, Linear, Notion, Stripe, Ramp,
   Duolingo, Airbnb, Vercel, Instacart, Discord, Retool, Webflow…).
3. **06 (privacy):** top crop clips the "Job search" section header and leaves a
   floating white pill fragment. Fix the crop offset per-shot.
4. **iPad set:** the frame.py comment admits cropping around "a stray simulator
   corner artifact" — fix at capture (clean status-bar override), don't crop around.
5. **Headline accent consistency:** #1 and #3 accent one word in terracotta; #2/#4/#6
   don't. Accent the one payoff word in every headline, or none.
6. **Caption tightening:** "We check it's still open before you tap through" → the
   punchier "Re-checked before you ever see it."

- [x] **Icon** — Classic / Midnight / Mono ship; legible at Home-Screen size
- [ ] Fix screenshots 2, 3, 6 + iPad artifact per the review above
- [ ] Add the icon-variants frame (#5)
- [ ] Regenerate all sets: 6.9″ (1320×2868), 6.5″ (1242×2688), 13″ iPad (2048×2732)
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
