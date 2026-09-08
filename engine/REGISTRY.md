# The company registry — scaling from ~65 to ~1,500

The registry (`engine/companies.json`) is the moat. Rolecall's promise — *every live
product-design role at a real US tech company* — is only as true as this list is complete.
The crawler is commodity (four public endpoints); knowing **which companies exist, where
they're HQ'd, and which ATS currently serves their jobs** is the work.

## Target

~1,500 US-headquartered, venture-backed or established product/consumer-tech companies
that employ in-house product designers. Not agencies, not consultancies, not staffing
firms, not hardware-only / enterprise-IT shops with no digital product surface.

At ~65 companies we see ~700 in-vertical live roles. Linear scaling puts ~1,500 companies
at **12,000–16,000 live design/PM roles** — enough that "complete" is a real claim and the
board refreshes daily without feeling thin.

## Where the names come from

| Source | Yield | Notes |
|---|---|---|
| **YC company directory** (`ycombinator.com/companies`, filter: active, USA) | ~2,000 active US | The single richest source. Filter to B2C + B2B SaaS with a product surface. |
| **a16z / Sequoia / Lightspeed / Accel / Greylock / Benchmark / Founders Fund portfolios** | ~1,500 combined, heavy overlap | Public portfolio pages. Bias toward Series A+ (they have design teams). |
| **Forbes Cloud 100, Enterprise Tech 30, Forbes Next Billion-Dollar Startups** | ~200 | Later-stage, larger design orgs. |
| **"Design-led company" lists** — Config (Figma) speaker companies, Designer Fund portfolio, Config/Layers sponsor lists, Dribbble/Read.cv company follows, the Designer Hangout & Hexagon UX job channels | ~300 | Highest signal for *quality* of design org — prioritise these. |
| **ATS discovery sweep** — for each candidate domain, probe the 4 endpoints with slug guesses | — | See below. |
| **Manual: who's hiring threads** (HN monthly, r/userexperience, ADPList) | ~50/mo | Ongoing trickle, good for freshness of the registry itself. |

De-dupe by primary domain. Keep a `sources` array per company so a bad list can be
audited out later.

## ATS detection

The public slug is almost always a deterministic function of the company name:

1. Candidate slugs: `name`, `name` lowercased with spaces removed, with spaces→`-`,
   with `inc`/`labs`/`hq`/`technologies` appended, the domain's second-level label.
2. Probe all four vendors for each candidate (`engine.ats.resolve_ats(slug)`):
   - Greenhouse `boards-api.greenhouse.io/v1/boards/{slug}/departments`
   - Ashby `api.ashbyhq.com/posting-api/job-board/{slug}`
   - Lever `api.lever.co/v0/postings/{slug}?mode=json`
   - Workable `apply.workable.com/api/v1/widget/accounts/{slug}?details=true`
3. First vendor with a **non-empty** feed wins. Record `ats`, `slug`, and
   `ats_confidence` (exact-name-match vs. guessed).
4. No hit on any vendor → park in `unresolved.json`. These are companies on Rippling,
   Workday, iCIMS, BambooHR, Teamtailor, SmartRecruiters, Personio, Recruitee,
   Comeet, or a bespoke page. Greenhouse/Ashby/Lever/Workable cover an estimated
   **60–70%** of this vertical; the rest is Phase 2:
   - Add **Recruitee, Personio, SmartRecruiters, Teamtailor, Ashby-embed** adapters
     (all have public JSON) — cheap, gets to ~80%.
   - **Workday / Rippling / bespoke**: the AI-scrape long tail. A fetch + small-model
     extraction pass, gated behind a per-field confidence score, never shown as
     "verified" until a structured re-check passes.

## Migration drift — companies switch ATS

Observed in this seed: **Vercel and Mercury both moved Ashby → Greenhouse** in 2026. A
registry entry whose declared `ats` starts returning an empty feed has almost always
migrated, not stopped hiring.

`python -m engine resolve` re-probes every slug against all four vendors and prints:
- `MOVED  <id>  ashby -> greenhouse` — edit `companies.json`
- `DEAD   <id>  no vendor returns a feed` — company folded, went private, or moved to an
  ATS we don't support yet → move to `unresolved.json`, don't just delete (re-check monthly)

Run `resolve` weekly in Phase 1, then nightly as a pipeline step. Alert if > 2% of the
registry drifts in one run (usually means an endpoint shape changed, not 30 migrations).

## Keeping `hq = US` honest

The vertical is explicitly *US* companies. Non-US companies with big US offices
(1Password/CA, Miro/NL, Cohere/CA, Airwallex/AU, Monzo/Revolut/UK, Nubank/BR) are
**excluded** from the seed even though their feeds resolve — including them quietly
broadens the promise and makes "complete" unfalsifiable.

- Set `hq` from Crunchbase / PitchBook / the company's own "About" page, not from where
  a given role is located.
- A US-incorporated, remote-first company (Zapier, GitLab-style) counts as `hq = US`.
- When in doubt, exclude and note it in `unresolved.json` with a reason. It's better to
  under-claim coverage than to over-claim it.
- Publish the coverage methodology. The honesty *is* the brand (see NORTH_STARS.md).

## Ongoing validation loop (once live)

1. **nightly** — `ingest` (feed pull + freshness), `resolve` drift check, `verify` on the
   oldest-checked 20% of live postings.
2. **weekly** — audit sample of 50 live postings, hand-checked; track rolling
   verified-live accuracy. Gate stays at ≥ 98%.
3. **monthly** — re-probe `unresolved.json`; sweep one new investor portfolio; prune
   companies with 0 roles for 90+ days to a `dormant` list (still re-checked, not shown).
4. **quarterly** — spot-check 30 known-hiring companies against the board by hand and
   publish the measured coverage number.
