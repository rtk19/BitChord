#!/usr/bin/env bash
# CI only: values come from GitHub Secrets. Never enable shell tracing here.
set -euo pipefail
: "${IOS_CERTIFICATE_P12_BASE64:?Missing distribution certificate}"
: "${IOS_CERTIFICATE_PASSWORD:?Missing certificate password}"
: "${IOS_PROVISIONING_PROFILE_BASE64:?Missing provisioning profile}"
: "${RUNNER_TEMP:?Run this script in GitHub Actions}"
signing_dir=$(mktemp -d "$RUNNER_TEMP/bitchord-signing.XXXXXX")
export BITCHORD_SIGNING_DIR="$signing_dir"
python3 <<'PY'
import base64, os, pathlib
root = pathlib.Path(os.environ['BITCHORD_SIGNING_DIR'])
for variable, filename in [('IOS_CERTIFICATE_P12_BASE64', 'certificate.p12'), ('IOS_PROVISIONING_PROFILE_BASE64', 'profile.mobileprovision')]:
    (root / filename).write_bytes(base64.b64decode(os.environ[variable], validate=True))
PY
keychain="$signing_dir/signing.keychain-db"
{
  echo "IOS_SIGNING_KEYCHAIN=$keychain"
  echo "IOS_SIGNING_DIR=$signing_dir"
} >> "$GITHUB_ENV"
password=$(openssl rand -hex 24)
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$signing_dir/certificate.p12" -P "$IOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$keychain"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "$HOME/Library/Keychains/login.keychain-db"
security cms -D -i "$signing_dir/profile.mobileprovision" > "$signing_dir/profile.plist"
profile_uuid=$(/usr/libexec/PlistBuddy -c 'Print UUID' "$signing_dir/profile.plist")
profile_name=$(/usr/libexec/PlistBuddy -c 'Print Name' "$signing_dir/profile.plist")
profile_team=$(/usr/libexec/PlistBuddy -c 'Print TeamIdentifier:0' "$signing_dir/profile.plist")
[[ "$profile_team" == "$APPLE_TEAM_ID" ]] || { echo 'The profile belongs to a different Apple team.' >&2; exit 1; }
mkdir -p "$HOME/Library/MobileDevice/Provisioning Profiles"
installed_profile="$HOME/Library/MobileDevice/Provisioning Profiles/$profile_uuid.mobileprovision"
cp "$signing_dir/profile.mobileprovision" "$installed_profile"
{
  echo "IOS_PROFILE_NAME=$profile_name"
  echo "IOS_INSTALLED_PROFILE=$installed_profile"
} >> "$GITHUB_ENV"
