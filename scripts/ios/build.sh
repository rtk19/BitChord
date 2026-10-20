#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
distribution=${1:-simulator}
case "$distribution" in simulator|unsigned|development|ad-hoc|app-store-connect) ;; *) echo "Unknown distribution: $distribution" >&2; exit 1;; esac
[[ $(uname) == Darwin ]] || { echo 'iOS builds require macOS and Xcode.' >&2; exit 1; }
[[ -d ios/BitChord.xcodeproj ]] || bash scripts/ios/prepare.sh
mkdir -p ios/build
args=(-project ios/BitChord.xcodeproj -scheme BitChord -configuration Release)
args+=("PRODUCT_BUNDLE_IDENTIFIER=${IOS_BUNDLE_ID:-io.github.rtk19.BitChord}")
version=${IOS_VERSION:-$(python3 scripts/ios/version.py)}
args+=("MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=${IOS_BUILD_NUMBER:-1}")
if [[ "$distribution" == simulator ]]; then
  xcodebuild "${args[@]}" -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath ios/build/simulator CODE_SIGNING_ALLOWED=NO build
  exit 0
fi
archive="$root/ios/build/BitChord.xcarchive"
if [[ "$distribution" == unsigned ]]; then
  xcodebuild "${args[@]}" -destination 'generic/platform=iOS' -archivePath "$archive" CODE_SIGNING_ALLOWED=NO archive
  echo 'Unsigned device archive created. This cannot be installed on an iPhone.'
  exit 0
fi
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your Apple Developer Team ID}"
args+=("DEVELOPMENT_TEAM=$APPLE_TEAM_ID")
if [[ -n ${IOS_PROFILE_NAME:-} ]]; then
  args+=(CODE_SIGN_STYLE=Manual "PROVISIONING_PROFILE_SPECIFIER=$IOS_PROFILE_NAME" "CODE_SIGN_IDENTITY=${IOS_SIGNING_IDENTITY:-Apple Distribution}")
else
  args+=(CODE_SIGN_STYLE=Automatic -allowProvisioningUpdates)
fi
xcodebuild "${args[@]}" -destination 'generic/platform=iOS' -archivePath "$archive" archive
export IOS_EXPORT_DISTRIBUTION="$distribution"
python3 - "$root/ios/build/ExportOptions.plist" <<'PY'
import os, plistlib, sys
methods = {'development': 'debugging', 'ad-hoc': 'release-testing', 'app-store-connect': 'app-store-connect'}
profile = os.environ.get('IOS_PROFILE_NAME')
options = {
    'method': methods[os.environ['IOS_EXPORT_DISTRIBUTION']],
    'teamID': os.environ['APPLE_TEAM_ID'],
    'signingStyle': 'manual' if profile else 'automatic',
    'manageAppVersionAndBuildNumber': False,
    'stripSwiftSymbols': True,
}
if profile:
    options['provisioningProfiles'] = {os.environ.get('IOS_BUNDLE_ID', 'io.github.rtk19.BitChord'): profile}
with open(sys.argv[1], 'wb') as target:
    plistlib.dump(options, target)
PY
export_args=(-exportArchive -archivePath "$archive" -exportPath "$root/ios/build/export" -exportOptionsPlist "$root/ios/build/ExportOptions.plist")
[[ -n ${IOS_PROFILE_NAME:-} ]] || export_args+=(-allowProvisioningUpdates)
xcodebuild "${export_args[@]}"
echo "IPA: $root/ios/build/export/BitChord.ipa"
