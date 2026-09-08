# Release checklist — Rolecall iOS

## Before you archive

1. **Refresh the bundled board (P0-18).** The app ships `data/board.json` inside
   the IPA and trusts it because it's in the signed bundle — but nothing at
   runtime checks its age, so a stale one means fresh installs see a weeks-old
   "verified live" board until their first successful refresh.

   ```
   make release-board
   ```

   This runs `engine ingest → verify → export → sign`, copies the fresh board to
   `ios/Rolecall/Resources/board.json`, and runs the freshness check. **Commit
   the updated `ios/Rolecall/Resources/board.json`.**

2. **Confirm freshness** (also enforced automatically — see below):

   ```
   make check-board
   ```

   Must print `… — fresh (limit 3d)`. If it fails, go back to step 1.

3. Run the full test suite: `make test` (engine + iOS unit tests). All green.

4. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `ios/project.yml`,
   regenerate the project (`/Users/dj/bin/xcodegen generate --spec ios/project.yml`).

5. Archive in Xcode (Product → Archive) or:

   ```
   xcodebuild archive -project ios/Rolecall.xcodeproj -scheme Rolecall \
     -configuration Release -archivePath build/Rolecall.xcarchive
   ```

## Automatic guard

The **"Bundled board freshness (archive only)"** build phase on the `Rolecall`
target runs `scripts/check_board_fresh.py` during an archive (`ACTION=install`)
and **fails the archive** if `ios/Rolecall/Resources/board.json` is more than 3
days old. Debug and test builds skip it. Override the threshold for a build with
`BOARD_MAX_AGE_DAYS` if you ever genuinely need to (you shouldn't).

## Signing key

Board signing, key rotation, and the loss/compromise runbook:
[`docs/signing-key-runbook.md`](signing-key-runbook.md).
