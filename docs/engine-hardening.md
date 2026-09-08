# Engine hardening backlog

Work items from the Apple Fellows review of Rolecall's two engines (the Python
ingest/classify engine in `engine/`, and the on-device data layer in
`ios/Rolecall/Data/` + `ios/Shared/`), 2026‑09‑08.

**North Star for this work:** the two engines make one sentence true — *"every
role here is real and still open, taken only from the company's own public
feed"* — without ever spending the user's identity, data, or battery on
anything they didn't ask for.

Each item below is self-contained: a fellow (or an agent) can pick one up,
work it end to end, and land it without touching the others. Priority order is
the Judge's; `P0-1` is the one to do first.

| ID | Title | Lane | Effort |
|----|-------|------|--------|
| P0-1 | Move board decode / sanitise / merge off the main actor | Performance | M |
| P0-2 | `check_url` scheme + SSRF hardening | Security | S |
| P0-3 | Split `engine sign` into its own network-free CI job | Security / Release | S |
| P0-4 | `FreshnessChecker` TTL cache + Wi-Fi-only toggle | Performance / Privacy | M |
| P0-5 | "Leaves within the hour" copy vs the 6-hourly cron | Product integrity | S |
| P0-6 | `isPlausibleReplacement` — reject per-company feed collapse | Product integrity | S |
| P0-7 | Ship board + signature as one atomically-fetched artifact | Networking | M |
| P0-8 | `engine/tests/test_ed25519.py` — RFC 8032 vectors | Supply chain | S |
| P0-9 | Pin every GitHub Action to a commit SHA | Supply chain | S |
| P0-10 | Version the classifier + held-out family test set | Data | M |
| P0-11 | `INCLUDE_PM` → declared config, stamped into `board.json` | Data | S |
| P0-12 | `companies.json` schema guard + split `pipeline.py` | Architecture | M |
| P0-13 | Engine enforces `https://` on every exported role URL | Security | S |
| P0-14 | Harden the engine SQLite session (WAL, busy_timeout, one txn) | Architecture | S |
| P0-15 | Slim `Digest.runBackgroundRefresh` | Architecture | S |
| P0-16 | Stop leaking full URL lists to CI logs | Privacy | S |
| P0-17 | Key-loss / key-rotation runbook | Release | S |
| P0-18 | Verify the bundled `board.json` is fresh at release | Release | S |

---

## P0-1 — Move board decode / sanitise / merge off the main actor

**Lane:** Performance & Power · **Effort:** M · **The Judge's "one thing first."**

### Problem
`BoardStore` is `@MainActor` and does a full JSON decode + two O(n)
`sanitized()` passes + an O(n) `merging()` + two file writes **synchronously on
the main thread** — in `init` (before the first frame) and again in `refresh()`
(every pull-to-refresh and every background wake). At today's ~625 roles it's a
~10 ms blip. At the 1,500-company registry goal that `engine/companies.json`
names as the moat, it is a 50–100 ms main-thread hang at every cold launch —
the opposite of the "content on the first frame, no spinner" intent.

### Evidence
- `ios/Rolecall/Data/BoardStore.swift:10` — `@MainActor final class BoardStore`
- `ios/Rolecall/Data/BoardStore.swift:38-45` — `init` decode + `sanitized()` ×2 + `merging()` + `SharedContainer.writeBoard()`, all sync
- `ios/Rolecall/Data/BoardStore.swift:76-85` — `refresh()` decode + `sanitized()` + `merging()` + `Set(board.roles.map(\.id))` on the main actor
- `ios/Shared/SharedContainer.swift:38-44` — `writeBoard` writes the whole (pretty-printed) board **twice** (App Group + Application Support)
- `ios/Shared/Board.swift:26` — `encoded()` uses `.prettyPrinted` for a machine-read cache file

### Fix
1. Make decode/sanitise/merge a `nonisolated` (or free) async function that
   takes `Data` and returns a `Board` value type; `await` it and assign the
   result back on `@MainActor`.
2. For `init`: load the bundled snapshot synchronously (it must be on the first
   frame) but move the *cache read + merge* into a `Task` that publishes when
   ready. The bundled board carries the app on frame 1; the merged board
   swaps in a beat later.
3. Drop `.prettyPrinted` from `Board.encoded()` when it's used for the cache
   file (keep it only where a human reads the output, if anywhere).
4. `writeBoard`: when the App Group container is available, write only that;
   skip the Application Support duplicate. Keep the local fallback only for
   the unsigned-simulator case.
5. Do the writes off the main thread.

### Acceptance criteria
- [ ] `BoardStore.init` returns in < 2 ms with a 5,000-role bundled board (measure with `os_signpost` / a unit test on a large fixture).
- [ ] `refresh()` does no JSON decode or array/dict work on the main actor (verify: the heavy call is `await`ed on a background executor).
- [ ] Cold-launch time-to-first-frame with a 5,000-role board is within 5 ms of an empty board (Instruments, Time Profiler).
- [ ] The board is written to disk at most once per refresh on a provisioned device.
- [ ] Existing `BoardStore` / merge tests still pass; add one with a multi-thousand-role fixture.

### Risk if skipped
The app stops launching instantly exactly when the registry — the strategic
moat — reaches the size the plan depends on.

---

## P0-2 — `check_url` scheme + SSRF hardening

**Lane:** Security · **Effort:** S

### Problem
`check_url()` takes a URL straight from an ATS feed and hands it to
`urllib.request.urlopen` with no scheme allowlist and no redirect-target
filtering. `file://`, `ftp://`, `http://127.0.0.1:…`, `http://169.254.169.254/…`
are all fetched — from inside the CI job that holds `ROLECALL_SIGNING_KEY`.
Today it's a blind SSRF with a near-useless 1-bit oracle (the body is only
substring-matched and never stored), and a GitHub runner has nothing worth
stealing — but "attacker-influenced URL in the process that has the signing
key" is a shape that shouldn't exist.

### Evidence
- `engine/net.py:44-63` — `check_url`, no scheme check, default redirect handling
- `engine/pipeline.py:175` — `code, final_url, body = check_url(p["url"])` where `p["url"]` came from the feed
- `engine/ats.py:65,93,116,142` — the URL originates from `absolute_url` / `jobUrl` / `hostedUrl` / `url` in the ATS JSON
- `engine/pipeline.py:187-192` — the body is used only for a boolean; `final_url` is not stored

### Fix
1. In `net.py`, before any request: reject a URL whose scheme is not
   `http`/`https`.
2. Resolve the host and reject loopback / private (RFC 1918) / link-local /
   ULA / `.local`. Re-check after each redirect (install a custom
   `HTTPRedirectHandler` that re-validates, or disable auto-redirect and
   follow manually with a hop cap of ≤ 5).
3. Cap the redirect chain explicitly.
4. Apply the same guard in `get_json` for symmetry (its URLs are
   engine-constructed today, but defence in depth).

### Acceptance criteria
- [ ] `check_url("file:///etc/hostname")` returns `(0, url, "")` without opening the file.
- [ ] `check_url("http://169.254.169.254/")` and `http://127.0.0.1:8080/` are refused pre-flight.
- [ ] A posting URL that 302s to `http://localhost/` is refused at the redirect, flagged ambiguous, not followed.
- [ ] A normal `https://boards.greenhouse.io/...` check still works unchanged.
- [ ] New unit tests in `engine/tests/` cover scheme, private-IP, and redirect-to-private cases.

### Risk if skipped
A hostile or compromised registry/feed entry can make the signing job perform
arbitrary internal requests.

---

## P0-3 — Split `engine sign` into its own network-free CI job

**Lane:** Security / Release · **Effort:** S

### Problem
`ROLECALL_SIGNING_KEY` is exposed to a step that has just run three commands
that fetch and parse data from the public internet (`ingest`, `verify`,
`export`). The commands are stdlib-only and memory-safe so RCE is unlikely, but
the blast radius of any bug on that path is "an attacker signs a board."

### Evidence
- `.github/workflows/deploy.yml:42-54` — one step runs `ingest`, `verify`, `export`, `stats`, then `sign`, with `ROLECALL_SIGNING_KEY` in its `env`

### Fix
1. Job A (`build-board`): `ingest → verify → export → stats`, uploads
   `data/board.json` (+ the SQLite DB for the cache) as a workflow artifact.
   No signing secret in this job.
2. Job B (`sign-board`, `needs: build-board`): downloads the artifact, runs
   only `engine sign`, uploads `board.json.sig`. `ROLECALL_SIGNING_KEY` only
   here. No `pip install`, no network calls.
3. Job C (`deploy`, `needs: sign-board`): builds the site, deploys to
   Cloudflare.
4. Keep the existing "no key → loud warning" fallback in Job B.

### Acceptance criteria
- [ ] `ROLECALL_SIGNING_KEY` appears in exactly one job's `env`, and that job runs no command that opens a socket.
- [ ] A full run still produces a matching `board.json` + `board.json.sig` at the edge.
- [ ] The engine-state cache still round-trips (Job A restores + saves it).
- [ ] `grep -rn ROLECALL_SIGNING_KEY .github/` shows one occurrence.

### Risk if skipped
The signing key shares a process with attacker-influenceable input parsing.

---

## P0-4 — `FreshnessChecker` TTL cache + Wi-Fi-only toggle

**Lane:** Performance / Privacy · **Effort:** M

### Problem
`FreshnessChecker.check()` hits the network on every `RoleDetailView` `.task`
with no result cache — browse 25 roles, reopen 5, and that's 30 GETs of up to
200 KB each (~4–6 MB of cellular the user didn't ask for), the same role
re-checked minutes apart. There's also no way to disable it or hold it to
Wi-Fi, which a privacy-first job board invites.

### Evidence
- `ios/Rolecall/Data/FreshnessChecker.swift:47-75` — `check()` always performs the request
- `ios/Rolecall/Data/FreshnessChecker.swift:70` — reads `data.prefix(200_000)`
- `ios/Rolecall/Views/RoleDetailView.swift:30` — `.task { await runCheck() }` on every appearance
- `ios/Rolecall/Views/RoleDetailView.swift:31` + `RoleListView.swift:102` — two always-on `Timer.publish(every: 60)` for relative-time text

### Fix
1. An in-memory `actor FreshnessCache` keyed by `role.id` → `(Status, Date)`.
   `check()` returns the cached status if it's < ~15 min old. Cap the cache
   (LRU, ~200 entries).
2. Add `AppSettings.checkLinksOnWiFiOnly` (default `true`). When on and the
   path is cellular (`NWPathMonitor`), `check()` short-circuits to
   `.couldNotCheck` with a distinct "not checked — you're on cellular" detail
   line, and offers a "Check now" button.
3. Bump both relative-time timers from 60 s to 300 s.
4. Optionally: coalesce the two timers into one shared publisher.

### Acceptance criteria
- [ ] Opening the same role twice within 15 min performs one network request (verify with a mock `URLProtocol` counting calls).
- [ ] With the toggle on and a simulated cellular path, `check()` makes no request and the UI shows the cellular state + a manual override.
- [ ] With the toggle off, behaviour is unchanged.
- [ ] `Settings` shows the toggle in the Privacy or Job-search section, default on.
- [ ] Relative-time labels update on a 5-minute cadence; no visible regression.

### Risk if skipped
Metered-data users pay for background fetches they didn't request; heavy
browsing sessions do redundant work.

---

## P0-5 — "Leaves within the hour" copy vs the 6-hourly cron

**Lane:** Product integrity · **Effort:** S

### Problem
The role page states *"The moment {company} closes this role, it leaves Rolecall
— usually within the hour."* The engine refreshes four times a day, so the
board-level claim is false by design; worst case is ~6 h + deploy time. The
on-device live check catches a stale entry when the user opens a role, but the
sentence describes the board, not the check.

### Evidence
- `ios/Rolecall/Views/RoleDetailView.swift` — `sourceNote`, string: `"… it leaves Rolecall — usually within the hour."`
- `.github/workflows/deploy.yml:11` — `cron: "17 */6 * * *"  # refresh the board four times a day`

### Fix
Pick one:
- **A (cheap, honest):** change the copy to *"…usually within a few hours"* (or
  *"by the next refresh"*). Also review the landing page / App Store copy for
  the same claim.
- **B (if the promise matters):** tighten the cron to hourly (`17 * * * *`),
  confirm the ingest + verify + deploy comfortably fit an hour at the target
  registry size (see P0-12 for the serial-fetch concern), then keep the copy.

Recommend **A** now, revisit **B** after P0-12.

### Acceptance criteria
- [ ] No user-facing surface (app, `web/`, ASO text) claims a refresh cadence faster than the cron actually delivers.
- [ ] `grep -rn "within the hour" .` returns nothing user-facing, or the cron matches it.

### Risk if skipped
The product overclaims its core promise in writing — the one thing the "honest,
no ghost jobs" positioning cannot afford.

---

## P0-6 — `isPlausibleReplacement` — reject per-company feed collapse

**Lane:** Product integrity · **Effort:** S

### Problem
A signed board that is newer, non-empty, and ≥ 50 % of the current size is
accepted. A bad ingest day where a chunk of ATS feeds 403 produces a
55 %-size, newer, validly-signed board that replaces the good one — the user
silently loses ~45 % of their roles until the next healthy run. The 50 % floor
catches catastrophic truncation but not the common partial-failure shape.

### Evidence
- `ios/Shared/Board.swift:79-83` — `isPlausibleReplacement` checks only `generatedUTC >`, `!roles.isEmpty`, `roles.count * 2 >= current.roles.count`
- `engine/pipeline.py:111-118` — a company whose feed throws is `continue`d; `mark_gone_for_company` (`store.py:91`) only runs for companies that *were* fetched
- `engine/pipeline.py:344-351` — `export()` emits every row with `status='live'`

Likely mitigant to confirm first: because a failed `fetch_company` skips
`mark_gone_for_company`, that company keeps its prior `live` rows in the DB and
`export()` still emits them — so a feed *error* does not shrink `board.json`.
The residual risk is a feed that returns a **valid but partial** payload (empty
list, or half the jobs) — that *would* mark the rest `gone` and shrink the
board.

### Fix
1. Confirm the mitigant in code. If a failed `fetch_company` provably leaves
   that company's prior `live` rows in `board.json`, the client-side risk is
   limited to partial-payload feeds — note that here and size the fix to just
   step 3.
2. If a failed feed *can* shrink a company's presence (e.g. partial JSON, or a
   feed that returns an empty list rather than erroring), add to
   `isPlausibleReplacement`: build `{company: count}` for old and new; reject
   if any company that had ≥ N roles drops to 0, or if > X % of companies lose
   > half their roles in one step.
3. Independently: have the **engine** refuse to `export` / `sign` a board
   whose live count fell > 30 % vs the last committed board (fail the CI run
   loudly instead of publishing a thin board).

### Finding (2026-09-08, verified in code)

**A failed `fetch_company` does not shrink `board.json`.** Code path:

- `engine/pipeline.py` `ingest()` — `rows = fetch_company(c)` is wrapped in
  `try/except Exception`; on any error the loop does `continue` **before**
  reaching `store.mark_gone_for_company(...)`.
- `engine/store.py` `mark_gone_for_company()` is the *only* code that flips a
  posting to `status='gone'` from feed absence, and it is keyed on the
  `seen_keys` collected in that same iteration — so if the iteration is skipped,
  none of that company's rows are touched.
- `engine/pipeline.py` `export()` emits every row `WHERE status = 'live'`, so
  the company keeps its full prior presence in the board.
- After P0-2, `get_json` raises `RuntimeError` for non-2xx / blocked / partial
  transport failures, which is caught the same way — still no shrink.

So the client-side per-company check (step 2) is **not** needed: a feed *error*
cannot gut a company. The one residual path is a feed that returns HTTP 200 with
a *valid but partial* body (an empty `jobs` array, or half the list) — that
would populate `seen_keys` short and `mark_gone_for_company` would retire the
rest. That is an engine-side concern, addressed by step 3 only.

**Implemented:** step 3. `export()` reads the count of the board already on disk
(the previous run's, restored from the CI cache) and refuses — non-zero exit,
`::error::` annotation — to write a board whose live count fell more than 30%
(`BOARD_SHRINK_LIMIT`). `ROLECALL_ALLOW_BOARD_SHRINK=1` overrides for a genuine
prune. Steps 1–2 (client `isPlausibleReplacement`) intentionally left as-is.

### Acceptance criteria
- [x] A written note in this file stating whether a failed feed shrinks `board.json` (with the code path).
- [ ] If it can: a test where the candidate board has company X at 0 (was 40) and the replacement is rejected. — _N/A: a failed feed provably cannot; see finding._
- [x] Engine: a synthetic "half the companies returned empty" board fails `export` with a non-zero exit and a clear message.

### Risk if skipped
One bad upstream morning quietly halves a user's board.

---

## P0-7 — Ship board + signature as one atomically-fetched artifact

**Lane:** Networking & Systems · **Effort:** M

### Problem
`board.json` and `board.json.sig` are two separate GETs. During every Cloudflare
deploy (4×/day) there's a window where the edge serves a new board against a
stale cached signature (or vice versa) — the check fails and refresh silently
no-ops. Correct (fail-closed) but "pull-to-refresh does nothing" is a normal
invisible state for ~a minute, four times a day. The `_headers` cache rule also
covers `board.json` but not `board.json.sig`, so their edge TTLs can diverge.

### Evidence
- `ios/Rolecall/Data/BoardStore.swift:60` (board GET) then `:71` → `fetchSignature()` `:92-101` (separate GET)
- `web/build.py` `HEADERS_FILE` — `Cache-Control` rule for `/board.json`, none for `/board.json.sig`

### Fix
Preferred: publish a single `board.v2.json` envelope
`{ "sig": "<hex>", "board": { …existing board… } }`. The engine writes it, the
app fetches one URL, verifies `sig` over the canonical bytes of the `board`
sub-object (define canonicalisation: the exact serialisation the engine emits),
then decodes. Keep the old two-file layout for one release for older clients.

Cheaper interim: give `board.json.sig` an identical `Cache-Control` to
`board.json`, and on a signature mismatch have the app re-fetch **both** once
(cache-busting) before giving up — closes most of the deploy window.

### Acceptance criteria
- [ ] Either one request fetches board+sig, or a mismatch triggers exactly one atomic re-fetch of the pair.
- [ ] `web/dist/_headers` gives board and signature the same cache policy.
- [ ] A test simulating "new board, old sig" results in the app retrying and then succeeding (not a silent no-op).
- [ ] No regression in the 8 MB cap / 15 s timeout / signature-before-decode ordering.

### Risk if skipped
Remote refresh is unreliable for minutes after every publish; users can't tell.

---

## P0-8 — `engine/tests/test_ed25519.py` — RFC 8032 vectors

**Lane:** Supply chain · **Effort:** S

### Problem
`engine/ed25519.py` is a vendored implementation and it is the one primitive
that makes "you can trust this board" true — but `engine/tests/` contains only
`test_classify.py`. There is no committed regression test for signing/verify.

### Evidence
- `engine/ed25519.py:1-7` — vendored, "adapted from the reference implementation"
- `engine/tests/` — `__init__.py`, `test_classify.py` only

### Fix
1. Add `engine/tests/test_ed25519.py` with **all** RFC 8032 §7.1 test vectors
   (empty message, 1-byte, 2-byte, the 1023-byte one, the SHA-512(abc) one):
   assert `publickey(sk) == pk`, `sign(msg, sk) == sig`, `verify(sig, msg, pk)
   is True`.
2. Negative cases: flip one bit of `sig`, of `msg`, of `pk` → `verify` returns
   `False` (never raises).
3. A round-trip test: `keygen()` → sign a random 200 KB blob → verify True;
   tamper → verify False.
4. Cross-check: sign with `engine/ed25519.py`, verify the same signature with
   CryptoKit is out of scope for Python CI, but add a Swift test in
   `RolecallTests` that verifies a **known** `(pubkey, message, signature)`
   triple produced by the Python impl (commit the triple as a fixture) — this
   is the real "the two implementations agree" guard.
5. Wire both into whatever runs `test_classify.py` (and into CI).

### Acceptance criteria
- [ ] `python -m engine.tests.test_ed25519` passes all RFC 8032 vectors.
- [ ] Bit-flip negative cases pass.
- [ ] A `RolecallTests` case verifies a Python-produced signature fixture with CryptoKit.
- [ ] CI runs the engine test suite and fails the build on a regression.

### Risk if skipped
A silent change to the vendored crypto (or a Python version quirk) could break
signing or, worse, weaken verification, with nothing to catch it.

---

## P0-9 — Pin every GitHub Action to a commit SHA

**Lane:** Supply chain · **Effort:** S

### Problem
`actions/checkout@v4`, `actions/setup-python@v5`,
`actions/cache/restore@v4`, `actions/cache/save@v4`, and
`cloudflare/wrangler-action@v3` are pinned by moving tag. A compromised tag on
any of them runs in the job that holds `ROLECALL_SIGNING_KEY` (until P0-3) and
`CLOUDFLARE_API_TOKEN`.

### Evidence
- `.github/workflows/deploy.yml:27,29,37,66,85` — all `@vN` tags

### Fix
1. Replace each `@vN` with `@<full-40-char-SHA>  # vN.n.n`.
2. Add a Dependabot config (`.github/dependabot.yml`, `package-ecosystem:
   "github-actions"`) so the SHAs get PR'd forward on a schedule.
3. Keep `permissions: contents: read` (already correct) and add explicit
   minimal `permissions` to each job after the P0-3 split.

### Acceptance criteria
- [ ] No `uses:` line in `.github/workflows/` references a tag or branch.
- [ ] `.github/dependabot.yml` covers `github-actions`.
- [ ] A run still passes end to end.

### Risk if skipped
Third-party action compromise runs with the deploy token and (pre-P0-3) the
signing key.

---

## P0-10 — Version the classifier + held-out family test set

**Lane:** Data & Classification · **Effort:** M

### Problem
The classifier is a growing regex cascade whose exclude list is explicitly
scar tissue (`# real false positives found in the classifier audit
(2026-09-08)`). At 1,500 companies it will over-block real roles or leak, and
there is no held-out set measuring *which*. The test file asserts only the
boolean match for most cases, never the family, so a "Content Designer" landing
in `research` vs `design` would pass silently.

### Evidence
- `engine/classify.py:20-77` — `_DESIGN`, `_PM`, `_EXCLUDE` lists; `classify.py:52-62` scar-tissue comments
- `engine/tests/test_classify.py:6-20` — `SHOULD_MATCH` checks `ok` only, not `fam`, for 13/20 cases
- `engine/tests/test_classify.py:54-62` — `WANT_FAMILY` pins only 7 boundary cases

### Fix
1. Build `engine/tests/labelled_titles.jsonl` — a few hundred real
   `(title, department) → {is_target, family}` rows, sampled from actual
   ingests across many companies, hand-labelled once.
2. `test_classify.py`: assert *family* for every `is_target` row, and compute
   precision/recall against the labelled set; fail if either drops below a
   committed threshold.
3. Add a `classifier_version` string constant, bumped on any rule change, and
   thread it through to `board.json` (see P0-11 for the export mechanism).
4. `python -m engine audit` already measures verified-live accuracy — add an
   `audit --classify` mode that hand-checks *family* assignment on a sample.

### Acceptance criteria
- [ ] `labelled_titles.jsonl` exists with ≥ 200 rows spanning ≥ 20 companies.
- [ ] The test computes and asserts precision + recall against it.
- [ ] Every rule edit requires a `classifier_version` bump (documented in `engine/REGISTRY.md` or a `CONTRIBUTING` note).
- [ ] `board.json` carries `classifier_version`.

### Risk if skipped
Classification quality degrades invisibly as the registry — the moat — grows.

---

## P0-11 — `INCLUDE_PM` → declared config, stamped into `board.json`

**Lane:** Data & Classification · **Effort:** S

### Problem
`INCLUDE_PM = True` is a bare module constant. Flipping it silently adds or
removes every PM role from a "for designers" board, with no version stamp in
`board.json`, so the app can't tell which ruleset produced a given snapshot.

### Evidence
- `engine/classify.py:18` — `INCLUDE_PM = True`
- `engine/pipeline.py:352-363` — `export()` writes `{generated_utc, count, roles}` — no ruleset metadata

### Fix
1. Add a small `engine/config.py` (or a `"config"` block in `companies.json`)
   with `include_pm`, `classifier_version`, `vertical`.
2. `export()` writes a `meta` object into `board.json`:
   `{ "classifier_version": "...", "include_pm": true, "vertical": "product-design" }`.
3. `ios/Shared/Board.swift` decodes `meta` (optional, defaulted, so old
   snapshots still parse). Nothing in the UI needs it yet — it's for
   debuggability and future migrations.
4. Signature is still over the exact bytes, so `meta` is covered automatically.

### Acceptance criteria
- [ ] `board.json` has a `meta` object; the signed bytes include it.
- [ ] `Board` decodes with and without `meta` (test both).
- [ ] Changing `include_pm` is a one-line config edit, not a source edit, and shows up in `meta`.

### Risk if skipped
A board-wide content change leaves no trace — the opposite of the "honest"
positioning.

---

## P0-12 — `companies.json` schema guard + split `pipeline.py`

**Lane:** Software Architecture · **Effort:** M

### Problem
`pipeline.py` is one 366-line module still self-described as "the Week-0
verification spike," and it produces the signed artifact the whole product
trusts. `companies.json` has no schema check — a missing `slug` `KeyError`s
mid-ingest. Feed fetches are fully serial with up to ~64 s per failing company
(3 retries × ~20 s), which is fine at 40 companies and a CI-budget / staleness
problem at the planned ~1,500.

### Evidence
- `engine/pipeline.py:1` — `"""The Week-0 verification spike, as code."""`
- `engine/pipeline.py:113` — `rows = fetch_company(c)` with `c["slug"]` unchecked (`ats.py:160-164`)
- `engine/net.py:26-41` — `get_json` retries `retries=2` with `time.sleep(1.5 * (attempt+1))`, `timeout=20`
- `engine/pipeline.py:111` — serial `for c in companies`

### Fix
1. `engine/registry.py`: load + **validate** `companies.json` (every entry has
   `id`, `name`, `ats ∈ ADAPTERS`, `slug`); fail fast with the offending entry.
2. Split `pipeline.py` → `ingest.py`, `verify.py`, `resolve.py`, `report.py`
   (`stats`+`audit`), `export.py`; `__main__.py` dispatches. Keep behaviour
   identical; this is a move + a test that each command still runs.
3. Bound the ingest: a per-run wall-clock cap, and a bounded thread pool
   (e.g. 8 workers) for `fetch_company` — the ATS APIs are independent hosts.
   Keep the DB writes single-threaded (collect rows, then upsert).
4. Drop the docstring's "spike" language.

### Acceptance criteria
- [ ] A malformed `companies.json` entry fails `ingest` immediately with a message naming the entry.
- [ ] `ingest` of 40 companies is at least 4× faster wall-clock (parallel fetch) with identical DB output.
- [ ] Each `engine <cmd>` still works; a smoke test covers all of them.
- [ ] No module over ~150 lines.

### Risk if skipped
The artifact-producing code doesn't scale to the registry size the strategy
requires, and a typo in the moat data crashes the run.

---

## P0-13 — Engine enforces `https://` on every exported role URL

**Lane:** Security · **Effort:** S

### Problem
`export()` writes the feed's URL verbatim. The iOS app rescues the situation
with `Board.sanitized()`, but the *signed* artifact can still contain an
`http:` or `javascript:` apply link, and any other consumer (the `web/` job
pages, a future Android client) inherits the problem. Enforce it at the source.

### Evidence
- `engine/pipeline.py:356` — `"url": r["url"]` written straight through
- `ios/Shared/Board.swift:66-73` — `sanitized()` drops non-https on the client (the only current guard)
- `web/build.py` `render_job` — renders `role["url"]` into an `href` and JSON-LD

### Fix
1. In `export()` (or in `upsert_posting`, earlier): drop any role whose URL
   scheme isn't `https`. Log the count dropped.
2. Optionally normalise (strip fragments/tracking params) while there.
3. Keep the client-side `sanitized()` as defence in depth.

### Acceptance criteria
- [ ] A feed row with an `http://` URL never appears in `board.json`.
- [ ] The engine logs `dropped N non-https URLs` when it happens.
- [ ] `web/build.py` and the app both still render every remaining role.

### Risk if skipped
A non-https "Apply" link on a trust surface is a phishing vector, and it's
currently only blocked on one of several consumers.

---

## P0-14 — Harden the engine SQLite session

**Lane:** Software Architecture · **Effort:** S

### Problem
`store.connect()` opens SQLite with defaults — no WAL, no `busy_timeout`.
`ingest` commits per-company inside the loop and `verify` every 25 rows, so a
crash mid-run leaves a half-updated DB that the next `export` will sign.

### Evidence
- `engine/store.py:46-51` — `sqlite3.connect(...)`, `executescript(SCHEMA)`, no PRAGMAs
- `engine/pipeline.py:134` — `conn.commit()` inside the per-company loop
- `engine/pipeline.py:201` — `if checked % 25 == 0: conn.commit()`

### Fix
1. `connect()`: `PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; PRAGMA
   foreign_keys=ON; PRAGMA synchronous=NORMAL`.
2. `ingest`: one transaction for the whole run (or per-company savepoints that
   roll up), so the DB is never observed half-updated.
3. `export`: read within a transaction; refuse to write `board.json` if the
   most recent `runs` row for `kind='ingest'` has no `finished_utc` (i.e. the
   last ingest crashed).

### Acceptance criteria
- [ ] `connect()` sets the four PRAGMAs.
- [ ] Killing `ingest` mid-run and then running `export` refuses to publish and says why.
- [ ] A clean `ingest → export` is unchanged.

### Risk if skipped
A crashed ingest can produce a signed, internally-inconsistent board.

---

## P0-15 — Slim `Digest.runBackgroundRefresh`

**Lane:** Software Architecture · **Effort:** S

### Problem
The background-refresh task constructs `AppSettings()`, `SavedSearches()`,
`Store()` (the whole StoreKit stack) and `BoardStore()` from scratch and
`Task.sleep(400ms)` waiting for StoreKit's entitlement listener — a lot of
machinery inside a ~30 s budget to decide whether to post a "3 new roles"
notification. If `Store()` init ever hangs, digests silently stop.

### Evidence
- `ios/Rolecall/Data/Digest.swift:137-150` — `runBackgroundRefresh` builds all four objects; `Digest.swift:143` `Task.sleep(nanoseconds: 400_000_000)`

### Fix
1. Persist the last-known `isPlus` as a plain `Bool` in the App Group defaults
   whenever `Store.refreshEntitlements()` runs. The BG task reads that Bool —
   no StoreKit init, no sleep. Worst case: a lapsed subscriber gets one extra
   alert cycle, or a new subscriber waits one cycle for alerts. Acceptable.
2. `AppSettings` / `SavedSearches` are cheap `UserDefaults` reads — keep them.
3. `BoardStore()` in the BG task inherits P0-1's off-main decode.

### Acceptance criteria
- [ ] `runBackgroundRefresh` does not instantiate `Store` / touch StoreKit.
- [ ] No `Task.sleep` in the BG path.
- [ ] Alerts still fire in a device test where Plus is active and a saved search has new matches.

### Risk if skipped
The digest path has a StoreKit-shaped single point of failure and burns BG
budget on setup.

---

## P0-16 — Stop leaking full URL lists to CI logs

**Lane:** Privacy · **Effort:** S

### Problem
`audit()` and `stats()` print full posting URLs and company names to CI logs
on every 6-hourly run. If the repo is ever made public, the build-log history
becomes a timestamped "who is hiring designers" record.

### Evidence
- `engine/pipeline.py:196-199` — `print("  DEAD  ... {url}")` / `print("  ????  ... {url}")` in `verify`
- `engine/pipeline.py:258-259` — `audit` prints title + url
- `engine/pipeline.py:312-315` — `stats` prints per-company counts (counts are fine; the concern is URLs)

### Fix
1. In `verify`, log the company + flag + a truncated path, not the full URL
   (or gate full-URL logging behind a `--verbose` flag that CI doesn't pass).
2. `audit` is interactive and not run in CI — leave it, but note it.
3. Confirm the repo's intended visibility; if it stays private this is P3, but
   the fix is cheap enough to just do.

### Acceptance criteria
- [ ] A CI `verify` run logs no full posting URLs by default.
- [ ] `--verbose` still prints them for local debugging.

### Risk if skipped
Turning the repo public retroactively exposes a scrape history.

---

## P0-17 — Key-loss / key-rotation runbook

**Lane:** Release · **Effort:** S

### Problem
The signing key's only copy is a GitHub Actions secret. There is no documented
recovery if it's lost (the board can never be updated without an app release
that changes `board_pubkey.hex` + `BoardSignature.publicKeyHex`) and no second
key. The rotation stance lives in a code comment.

### Evidence
- `ios/Rolecall/Data/BoardSignature.swift:11` — "Rotating the key means shipping an app update — that's the point."
- `engine/sign.py:8-13` — key comes from `ROLECALL_SIGNING_KEY` env only

### Fix
Write `docs/signing-key-runbook.md`:
1. Where the key lives, who can access it.
2. Generate a **backup keypair now** with `engine keygen`; store the private
   key offline (password manager / paper). Do **not** wire it into CI. Commit
   nothing but a note that it exists.
3. Rotation procedure: bump `engine/board_pubkey.hex` +
   `BoardSignature.publicKeyHex`, ship an app update, cut over the CI secret,
   keep the old key valid server-side for one release cycle (or accept a hard
   cutover — document the choice).
4. Compromise procedure: what to do if the key leaks (rotate immediately;
   `isPlausibleReplacement` + `sanitized()` bound the damage in the meantime;
   expedite an app release).

### Acceptance criteria
- [ ] `docs/signing-key-runbook.md` exists and covers loss, rotation, compromise.
- [ ] A backup key has been generated and stored offline (confirmed, not committed).

### Risk if skipped
Losing the key bricks remote board updates until an App Store release; a leak
has no rehearsed response.

---

## P0-18 — Verify the bundled `board.json` is fresh at release

**Lane:** Release · **Effort:** S

### Problem
The app bundles `data/board.json` at build time and trusts it because it's
inside the signed IPA. Nothing checks its age. A release cut without re-running
the engine ships a weeks-old "verified live" board to every fresh install
until their first successful refresh.

### Evidence
- `ios/Rolecall/Data/BoardSource.swift:13-19` — `bundledBoard()` reads the bundle, no freshness assertion
- No pre-archive step regenerates `data/board.json`

### Fix
1. A build phase / CI check that fails the archive if
   `data/board.json`'s `generated_utc` is older than N days (e.g. 3).
2. Or: a `make release-board` step that runs `engine ingest → export → sign`
   and refreshes the bundled copy, run as part of the release checklist.
3. Add the check to `docs/` release notes.

### Acceptance criteria
- [ ] Archiving with a `board.json` older than the threshold fails with a clear message.
- [ ] The release checklist names the "refresh the bundled board" step.

### Risk if skipped
Fresh installs briefly show a stale board labelled "verified live."

---

## Not in scope / explicitly kept as-is (the Judge's "Ship")

- **Ed25519 board signing** — design, key handling, and check ordering
  (signature before decode before `isPlausibleReplacement`) are correct.
  `P0-3`, `P0-7`, `P0-8`, `P0-17` harden the *operation* around it, not the
  scheme.
- **Overall device-performance posture** — local-first, bundled snapshot, no
  APNs, no polling, background refresh capped at 6 h and gated on a feature
  being on. The perf items (`P0-1`, `P0-4`) are "before the registry scales,"
  not "broken today."
- **Overall security posture** — zero third-party runtime deps, one data host,
  ATS enforced, parameterised SQL, no analytics. The smallest plausible attack
  surface for this kind of product.
- **No certificate pinning on `rolecalljobs.com`** — deliberately unnecessary:
  the Ed25519 signature makes a valid-cert MITM unable to forge a board, which
  is exactly why the signing was added.
