# Rolecall — dev / release tasks. Engine is stdlib-only Python 3; no venv needed.

PY ?= python3
BUNDLED_BOARD = ios/Rolecall/Resources/board.json
BOARD_MAX_AGE_DAYS ?= 3

.PHONY: test test-engine test-ios check-board release-board site

## Run the engine test suite.
test-engine:
	$(PY) -m engine.tests

## Run the iOS unit tests (simulator).
test-ios:
	xcodebuild test -project ios/Rolecall.xcodeproj -scheme Rolecall \
		-destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
		-only-testing:RolecallTests

test: test-engine test-ios

## P0-18: fail if the board bundled into the app is older than BOARD_MAX_AGE_DAYS.
## Also wired as an Xcode archive build phase (see ios/project.yml).
check-board:
	$(PY) scripts/check_board_fresh.py $(BUNDLED_BOARD) --max-age-days $(BOARD_MAX_AGE_DAYS)

## Refresh the board bundled into the app: pull feeds, classify, export, sign, then
## copy the fresh board into the app resources. Run this before cutting a release.
## Needs ROLECALL_SIGNING_KEY in the environment for the sign step (optional locally —
## the bundled board is trusted because it's inside the signed IPA, the .sig is not
## shipped in the bundle).
release-board:
	$(PY) -m engine ingest
	$(PY) -m engine verify 250 || true
	$(PY) -m engine export
	@if [ -n "$$ROLECALL_SIGNING_KEY" ]; then $(PY) -m engine sign; else \
		echo "note: ROLECALL_SIGNING_KEY unset — skipped sign (fine for the bundled copy)"; fi
	cp data/board.json $(BUNDLED_BOARD)
	$(MAKE) check-board
	@echo "Refreshed $(BUNDLED_BOARD). Commit it, then archive the app."

## Build the static site into web/dist.
site:
	$(PY) -m web build --base-url "https://rolecalljobs.com"
