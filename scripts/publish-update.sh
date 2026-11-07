#!/bin/zsh
# Prepares (and optionally publishes) a Sparkle update for a signed, notarized app.
#
#   scripts/publish-update.sh <path/to/App.app> <slug>
#
# Writes dist/updates/<App>-<version>-<build>.zip and dist/updates/<slug>/appcast.xml.
# With PUBLISH_UPDATE=1 it also uploads them to the public repo Neto/spinoff-updates:
#   - the zip goes to a GitHub Release tagged <slug>-<version>-<build>
#   - appcast.xml goes to <slug>/appcast.xml on the main branch (the SUFeedURL in the app)
# Release notes: RELEASE_NOTES="Short text" (optional).
#
# The EdDSA private key that signs updates lives in the login Keychain (Sparkle generate_keys).
# Back it up once with:  ~/Library/Developer/Sparkle-2.10.0/bin/generate_keys -x <file>
# Without it, installed copies can never accept another update.
set -euo pipefail

APP="${1:?Usage: publish-update.sh <App.app> <slug>}"
SLUG="${2:?Usage: publish-update.sh <App.app> <slug>}"
UPDATES_REPO="Neto/spinoff-updates"
SPARKLE_VERSION="2.10.0"
SPARKLE_BIN="${SPARKLE_BIN:-$HOME/Library/Developer/Sparkle-$SPARKLE_VERSION/bin}"

if [[ ! -x "$SPARKLE_BIN/sign_update" ]]; then
  print "▸ Downloading Sparkle $SPARKLE_VERSION tools"
  mkdir -p "${SPARKLE_BIN:h}"
  curl -fsSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
    | tar -xJ -C "${SPARKLE_BIN:h}"
fi

PLIST="$APP/Contents/Info.plist"
NAME="$(/usr/libexec/PlistBuddy -c 'Print CFBundleName' "$PLIST")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST")"
MIN_OS="$(/usr/libexec/PlistBuddy -c 'Print LSMinimumSystemVersion' "$PLIST")"
FEED="$(/usr/libexec/PlistBuddy -c 'Print SUFeedURL' "$PLIST")"
TAG="$SLUG-$VERSION-$BUILD"

OUT="dist/updates"
mkdir -p "$OUT/$SLUG"
ZIP_NAME="$NAME-$VERSION-$BUILD.zip"
ZIP="$OUT/$ZIP_NAME"

# The pkg was notarized, which also notarizes the app inside it. Staple the app so the
# update opens offline without a Gatekeeper warning.
print "▸ Stapling $NAME.app"
xcrun stapler staple "$APP" || print -u2 "Warning: could not staple $APP (is it notarized?)"

print "▸ Zipping $ZIP_NAME"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

print "▸ Signing the update"
SIGNATURE="$("$SPARKLE_BIN/sign_update" "$ZIP")"   # sparkle:edSignature="…" length="…"
URL="https://github.com/$UPDATES_REPO/releases/download/$TAG/$ZIP_NAME"
DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
NOTES="${RELEASE_NOTES:-$NAME $VERSION}"

cat > "$OUT/$SLUG/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$NAME</title>
    <link>$FEED</link>
    <item>
      <title>$NAME $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <description><![CDATA[<p>$NOTES</p>]]></description>
      <enclosure url="$URL" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
EOF
print "Update ready: $ZIP"
print "Feed ready:   $OUT/$SLUG/appcast.xml"

if [[ "${PUBLISH_UPDATE:-0}" != "1" ]]; then
  print "Not published. To publish this update to everyone, run:"
  print "  PUBLISH_UPDATE=1 $0 \"$APP\" $SLUG"
  exit 0
fi

if ! gh repo view "$UPDATES_REPO" >/dev/null 2>&1; then
  print "▸ Creating the public repo $UPDATES_REPO"
  gh repo create "$UPDATES_REPO" --public --add-readme \
    --description "Sparkle update feeds for Spin and Grabb"
fi

print "▸ Uploading $ZIP_NAME to release $TAG"
gh release create "$TAG" "$ZIP" -R "$UPDATES_REPO" --title "$NAME $VERSION ($BUILD)" --notes "$NOTES"

# Publish the feed last, so the zip already exists when apps read it.
print "▸ Publishing $SLUG/appcast.xml"
SHA="$(gh api "repos/$UPDATES_REPO/contents/$SLUG/appcast.xml" --jq .sha 2>/dev/null || true)"
ARGS=(-X PUT "repos/$UPDATES_REPO/contents/$SLUG/appcast.xml"
  -f message="$NAME $VERSION ($BUILD)"
  -f content="$(base64 -i "$OUT/$SLUG/appcast.xml")")
[[ -n "$SHA" ]] && ARGS+=(-f sha="$SHA")
gh api "${ARGS[@]}" >/dev/null
print "Published. Installed copies of $NAME will offer $VERSION within a day."
