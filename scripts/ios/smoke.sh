#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
device=$(xcrun simctl list devices available --json | python3 -c 'import json,sys; devices=json.load(sys.stdin)["devices"]; print(next(d["udid"] for runtime, group in devices.items() if "iOS" in runtime for d in group if d.get("isAvailable") and d["name"].startswith("iPhone")))')
evidence() {
  xcrun xcresulttool export attachments --path ios/build/LaunchTests.xcresult --output-path ios/build/screenshots || true
  xcrun simctl spawn "$device" log show --last 10m --predicate 'process == "BitChord"' --style compact > ios/build/simulator.log 2>&1 || true
}
trap evidence EXIT
python3 - "$device" <<'PY'
import subprocess, sys
device = sys.argv[1]
subprocess.run(['xcrun', 'simctl', 'boot', device], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True, timeout=240)
PY
args=(-project ios/BitChord.xcodeproj -scheme BitChord -configuration Debug)
args+=(-destination "platform=iOS Simulator,id=$device" -derivedDataPath ios/build/tests)
args+=(-parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO)
xcodebuild "${args[@]}" build-for-testing
# Catch missing runtime libraries immediately instead of spending minutes in
# each XCTest launch timeout. This app is a Debug fixture launch, not playback.
python3 - "$device" <<'PY'
import pathlib, subprocess, sys
device = sys.argv[1]
app = 'ios/build/tests/Build/Products/Debug-iphonesimulator/BitChord.app'
bundle = 'io.github.rtk19.BitChord'
subprocess.run(['xcrun', 'simctl', 'install', device, app], check=True)
log = pathlib.Path('ios/build/preflight.log')
with log.open('w') as output:
    process = subprocess.Popen(['xcrun', 'simctl', 'launch', '--console', '--terminate-running-process', device, bundle, '--fixture'], stdin=subprocess.PIPE, stdout=output, stderr=subprocess.STDOUT)
    try:
        process.wait(timeout=8)
        raise RuntimeError('App exited during launch preflight: ' + log.read_text()[-6000:])
    except subprocess.TimeoutExpired:
        print('App survived the launch preflight.')
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
        subprocess.run(['xcrun', 'simctl', 'terminate', device, bundle], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
PY
xcodebuild "${args[@]}" -resultBundlePath ios/build/LaunchTests.xcresult \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 240 \
  -maximum-test-execution-time-allowance 240 test-without-building
