#!/bin/zsh
# Compila o Grabb. Não instala em /Applications; arraste o .app manualmente.
set -euo pipefail

if [[ -d /Applications/Xcode-beta.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
elif [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

PROJ="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJ"

"$PROJ/scripts/bundle-helpers.sh"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

xcodebuild -project Grabb.xcodeproj -scheme Grabb -configuration Debug \
  -destination 'platform=macOS,arch=arm64' build

APP="$(/usr/bin/find "${HOME}/Library/Developer/Xcode/DerivedData" \
  -path '*/Build/Products/Debug/Grabb.app' -type d 2>/dev/null \
  | /usr/bin/head -1)"

open -R "$APP"
print "Build pronto: $APP"
