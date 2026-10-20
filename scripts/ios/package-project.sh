#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root"
test -d ios/BitChord.xcodeproj
test -f ios/BitChord/Web/index.html
destination="$root/ios/build/project/BitChord-iOS"
mkdir -p "$destination"
rsync -a --delete ios/BitChord/ "$destination/BitChord/"
rsync -a --delete ios/BitChordUITests/ "$destination/BitChordUITests/"
rsync -a --delete --exclude xcuserdata ios/BitChord.xcodeproj/ "$destination/BitChord.xcodeproj/"
cp ios/OPEN_IN_XCODE.md "$destination/README.md"
cp LICENSE "$destination/LICENSE"
ditto -c -k --sequesterRsrc --keepParent "$destination" ios/build/BitChord-XcodeProject.zip
