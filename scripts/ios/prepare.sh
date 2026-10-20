#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
[[ $(uname) == Darwin ]] || { echo 'Preparing the Xcode project requires macOS.' >&2; exit 1; }
for tool in node pnpm xcodegen xcrun; do
  command -v "$tool" >/dev/null || { echo "Missing $tool. See IOS.md." >&2; exit 1; }
done
node -e 'if (Number(process.versions.node.split(".")[0]) < 22) process.exit(1)'
pnpm --dir web install --frozen-lockfile
BITCHORD_IOS=1 pnpm --dir web --filter @bitchord/app build
mkdir -p ios/BitChord/Web
rsync -a --delete web/app/dist/ ios/BitChord/Web/
mv ios/BitChord/Web/ios.html ios/BitChord/Web/index.html
mkdir -p ios/BitChord/Assets.xcassets/AppIcon.appiconset
xcrun swift scripts/ios/icon.swift Logo.png ios/BitChord/Assets.xcassets/AppIcon.appiconset/Icon.png
cat > ios/BitChord/Assets.xcassets/AppIcon.appiconset/Contents.json <<'JSON'
{"images":[{"filename":"Icon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
JSON
cat > ios/BitChord/Assets.xcassets/Contents.json <<'JSON'
{"info":{"author":"xcode","version":1}}
JSON
IOS_VERSION=${IOS_VERSION:-$(python3 scripts/ios/version.py)} xcodegen generate --spec ios/project.yml --project ios
