#!/bin/zsh
# Build a Release copy of BeebPab and install it into /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate -q
xcodebuild -project BeebPab.xcodeproj -scheme BeebPab -configuration Release \
  -derivedDataPath build -destination 'platform=macOS' build -quiet
osascript -e 'quit app "BeebPab"' 2>/dev/null || true
sleep 1
rm -rf /Applications/BeebPab.app
ditto build/Build/Products/Release/BeebPab.app /Applications/BeebPab.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/BeebPab.app
echo "Installed /Applications/BeebPab.app"
