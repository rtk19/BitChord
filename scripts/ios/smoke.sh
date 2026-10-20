#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
device=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; devices=json.load(sys.stdin)["devices"]; print(next(d["udid"] for runtime, group in devices.items() if "iOS" in runtime for d in group if d.get("isAvailable") and d["name"].startswith("iPhone")))')
xcodebuild -project ios/BitChord.xcodeproj -scheme BitChord -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" -derivedDataPath ios/build/tests \
  -resultBundlePath ios/build/LaunchTests.xcresult CODE_SIGNING_ALLOWED=NO test
xcrun xcresulttool export attachments --path ios/build/LaunchTests.xcresult --output-path ios/build/screenshots
