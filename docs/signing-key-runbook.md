# Board-signing key: loss, rotation, compromise runbook

_Owner: AvaResearch LLC. Last reviewed 2026-09-08 (P0-17)._

Rolecall's board is an Ed25519-signed artifact. The app ships one public key
compiled in and **only** accepts a `board.json` (or `board.v2.json` envelope)
signed by the matching private key. That is the whole trust model — a MITM with a
valid TLS cert still can't forge a board. The flip side: **the private key is
load-bearing, and rotating it requires an App Store release.**

---

## 1. Where the key lives

| Thing | Location | Who can touch it |
|---|---|---|
| **Live private key** | GitHub Actions secret `ROLECALL_SIGNING_KEY` on the `Rolecall` repo | Repo admins only. Not printed in logs (the `sign-board` job guards it). |
| **Live public key** | `engine/board_pubkey.hex` (committed) **and** `ios/Rolecall/Data/BoardSignature.swift` → `publicKeyHex` (compiled into the app) — the two must be equal | Anyone (it's public) |
| **Backup private key** | Offline only — password manager + optionally paper. Generated 2026-09-08, **not** in CI. | Repo admins |
| Backup public key | `<fill in: password-manager item name / who holds the paper copy>` | — |

The `sign-board` CI job is the *only* job that sees `ROLECALL_SIGNING_KEY`
(P0-3), and it runs exactly one network-free command (`python3 -m engine sign`).

### Backup key

A spare keypair was generated with `python3 -m engine keygen` on 2026-09-08 and
stored offline. It is **not** trusted by any shipped build and **not** in CI —
it only shortens the rotation path if the live key is lost or leaks.

- Where it is: `<fill in: e.g. "1Password → Rolecall vault → 'board-signing BACKUP key'"; paper copy in the office safe>`
- Its public key is recorded alongside it. Do **not** paste the private key here
  or anywhere in the repo.
- The private key file was written once to the operator's local scratchpad as
  `SIGNING-KEY-BACKUP-DO-NOT-COMMIT.txt` with move-it instructions, then deleted.

---

## 2. Routine rotation (no incident)

Do this if you simply want to cycle the key (e.g. an admin left the company).

1. **Generate** a new keypair — or use the backup key:
   `python3 -m engine keygen`. Keep the private key in a password manager.
2. **Bump the public key in two places, in one commit:**
   - `engine/board_pubkey.hex` → the new public key (one line, hex).
   - `ios/Rolecall/Data/BoardSignature.swift` → `static let publicKeyHex = "<new>"`.
3. **Ship an app release** with that change. Wait until it is live on the App
   Store and adopted by a meaningful share of users (check your update-adoption
   curve — typically give it 1–2 weeks).
4. **Cut over CI:** set the GitHub Actions secret `ROLECALL_SIGNING_KEY` to the
   new private key. The next scheduled build signs with it.
5. **Grace period:** the engine signs with exactly one key, so this is a hard
   cutover at step 4 — every client still on the old app version stops getting
   board updates until they update. That's acceptable for a routine rotation
   *because you waited at step 3*. If you need a true dual-signing window, that
   is a code change (emit `board.json.sig` **and** `board.json.sig2`, app tries
   both) — not currently implemented; add it before a rotation where you can't
   afford the hard cutover.
6. Update the table in §1 and this file's "Last reviewed" date. Retire the old
   private key from the password manager once adoption is ~complete.

---

## 3. Key lost (no longer have the private key, no evidence of leak)

Symptom: the CI secret was deleted/rotated by accident and no copy exists, or
the sole holder is unreachable.

- **Board updates stop.** Existing installs keep working from their last good
  board + the bundled snapshot + the on-device live check. Nothing breaks
  loudly; the board just goes stale.
- `sign-board` will hit the "no key" branch and emit
  `::warning::ROLECALL_SIGNING_KEY not set …`; `board.json` ships unsigned and
  clients reject it (fail-closed). The site's job pages still update.

**Recovery:**
1. If the **backup key** exists (§1): set `ROLECALL_SIGNING_KEY` to the backup
   private key, then do the rotation steps 2–4 above with the backup's *public*
   key. You are back to signed updates after the app release ships.
2. If there is **no backup**: generate a fresh keypair and do the full rotation
   (§2). Until the app release lands, the board cannot be updated remotely at
   all — plan an expedited release.
3. Either way: create the backup key you didn't have (`engine keygen`, store
   offline) before closing the incident.

**Prevention:** the backup key in §1 exists precisely so path 1 is always
available. Verify annually that someone can still retrieve it.

---

## 4. Key compromised (private key leaked, or suspected)

Examples: the secret was printed to a public log, a laptop with the paper copy
was stolen, a repo admin account was phished.

**Immediate (hours):**
1. **Rotate the CI secret now** to a key the attacker does not have — the backup
   key, or a freshly generated one. This stops the attacker from signing a board
   that *your CI* would publish. (They could still self-host a forged board, but
   they can't put it at `rolecalljobs.com` without also breaching Cloudflare.)
2. Rotate/lock any credential that shared a blast radius (Cloudflare API token,
   GitHub admin sessions).
3. Assess exposure: was a forged board ever actually served? Check Cloudflare
   deploy history and the committed `data/board.json` / git history for a board
   your pipeline didn't produce.

**What bounds the damage while you work:**
- A forged board still has to be *served from `rolecalljobs.com`* to reach the
  app — the app talks to exactly one host. The attacker needs the CDN too.
- `Board.isPlausibleReplacement` (newer + non-empty + not <50% size) and the
  engine's >30% shrink guard (P0-6) stop a forged board from silently gutting a
  user's list.
- `Board.sanitized()` drops any non-`https` apply link on-device (P0-13 also
  enforces it engine-side), so a forged board can't inject an `http://` /
  `javascript:` phishing link.
- Worst realistic case: an attacker who ALSO controls the CDN could show users a
  plausible board of fake-but-real-looking roles. The signature's job is to make
  that require two breaches, not one.

**Then (days):** ship an expedited app release with the new `publicKeyHex` /
`board_pubkey.hex` (rotation §2 steps 2–3), cut CI over fully, invalidate the old
key everywhere. Write up the incident and what let the key leak.

---

## 5. Quick reference

```
Generate a keypair:      python3 -m engine keygen
Sign locally (test):     ROLECALL_SIGNING_KEY=<hex> python3 -m engine sign
Public key, committed:   engine/board_pubkey.hex
Public key, in the app:  ios/Rolecall/Data/BoardSignature.swift  (publicKeyHex)
CI secret:               GitHub → repo → Settings → Secrets → ROLECALL_SIGNING_KEY
Signing job:             .github/workflows/deploy.yml  →  job "sign-board"
```

Rotation always = **bump both public-key locations → ship the app → then swap the
CI secret.** Never swap the CI secret first; that strands every current install.
