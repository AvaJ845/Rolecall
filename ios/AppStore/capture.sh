#!/usr/bin/env bash
#
# Capture the raw App Store screens for framing by frame.py.
#
#   ios/AppStore/capture.sh            # both device classes
#   ios/AppStore/capture.sh iphone     # just one
#   ios/AppStore/capture.sh ipad
#
# Boots the simulator, pins a clean 9:41 status bar (so the raw frames carry no
# stray clock / battery / carrier), runs RolecallUITests/ScreenshotTests, and
# exports the attachments into ios/AppStore/raw/<class>/0N-*.png.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="$HERE/../Rolecall.xcodeproj"
SCHEME="Rolecall"
ONLY="RolecallUITests/ScreenshotTests/test_captureAppStoreScreens"

IPHONE_NAME="iPhone 17 Pro Max"
IPAD_NAME="iPad Pro 13-inch (M5)"

want="${1:-all}"

udid_for() {
  xcrun simctl list devices available | grep -F "$1 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'
}

clean_status_bar() {
  local udid="$1" kind="$2"
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || xcrun simctl boot "$udid" >/dev/null 2>&1 || true
  if [ "$kind" = "ipad" ]; then
    xcrun simctl status_bar "$udid" override \
      --time "9:41" --batteryState charged --batteryLevel 100 \
      --wifiMode active --wifiBars 3 --cellularMode notSupported
  else
    xcrun simctl status_bar "$udid" override \
      --time "9:41" --batteryState charged --batteryLevel 100 \
      --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --cellularMode active --cellularBars 4
  fi
}

capture() {
  local kind="$1" name="$2"
  local udid; udid="$(udid_for "$name")"
  [ -n "$udid" ] || { echo "no simulator named '$name'"; exit 1; }
  echo "== $kind — $name ($udid)"

  clean_status_bar "$udid" "$kind"

  local result="/tmp/rc-$kind.xcresult"
  rm -rf "$result"
  xcodebuild test \
    -project "$PROJECT" -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,id=$udid" \
    -only-testing:"$ONLY" \
    -resultBundlePath "$result" \
    -quiet

  local dump="/tmp/rc-$kind-attach"
  rm -rf "$dump"; mkdir -p "$dump"
  xcrun xcresulttool export attachments --path "$result" --output-path "$dump"

  local raw="$HERE/raw/$kind"
  rm -f "$raw"/*.png
  mkdir -p "$raw"
  python3 - "$dump" "$raw" <<'PY'
import json, pathlib, re, shutil, sys
dump, raw = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
manifest = json.loads((dump / "manifest.json").read_text())
seen = set()
for test in manifest:
    for att in test.get("attachments", []):
        human = att.get("suggestedHumanReadableName") or att.get("exportedFileName", "")
        m = re.match(r"(0\d-[a-z]+)", human)
        if not m or m.group(1) in seen:
            continue
        seen.add(m.group(1))
        shutil.copyfile(dump / att["exportedFileName"], raw / f"{m.group(1)}.png")
        print("  ->", raw / f"{m.group(1)}.png")
if not seen:
    sys.exit("no 0N-* attachments found in the xcresult")
PY

  xcrun simctl status_bar "$udid" clear >/dev/null 2>&1 || true
}

if [ "$want" = "all" ] || [ "$want" = "iphone" ]; then capture iphone "$IPHONE_NAME"; fi
if [ "$want" = "all" ] || [ "$want" = "ipad" ]; then capture ipad "$IPAD_NAME"; fi

echo
echo "raw captures updated — now: python3 $HERE/frame.py"
