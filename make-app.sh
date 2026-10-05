#!/bin/zsh
# Builds Calbar.app, the minimal .app bundle that gives UNUserNotificationCenter
# a CFBundleIdentifier, and Calbar.dmg, the release artifact. Also renders the
# app icon through `Calbar --generate-icon` and iconutil.
#
# The bundle never contains a Google OAuth client: each user imports their
# own google-oauth.json from the app. The script fails if one ends up inside.
#
# Usage: ./make-app.sh [--install]
#   --install: also copies the bundle to /Applications.

set -euo pipefail
cd "$(dirname "$0")"

CONFIG="release"
APP="Calbar.app"
BUNDLE_ID="dev.calbar.app"
VERSION="0.5.1"
BUILD="18"

echo "▶ Building $CONFIG…"
swift build -c "$CONFIG"

BIN=".build/$CONFIG/Calbar"
[ -x "$BIN" ] || { echo "✗ binary not found: $BIN"; exit 1; }

echo "▶ Packaging $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Calbar"

# No SwiftPM resource bundle is copied. Calbar_Calbar.bundle only holds the
# dev OAuth client and its example, and the generated `Bundle.module`
# accessors look at the .app root, where a signed bundle cannot hold
# anything, so a copy in Contents/Resources would never be read anyway.

# ─── icon ───────────────────────────────────────────────────────────────────
echo "▶ Generating the .icns icon…"
ICON_TMP=$(mktemp -d)
ICONSET="$ICON_TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

# Calbar renders itself as a 1024×1024 PNG (CLI mode).
"$BIN" --generate-icon "$ICONSET/icon_512x512@2x.png" || {
    echo "✗ icon rendering failed"; exit 1;
}

# Sizes iconutil expects.
sips -z 16   16   "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_16x16.png"        >/dev/null
sips -z 32   32   "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_16x16@2x.png"     >/dev/null
sips -z 32   32   "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_32x32.png"        >/dev/null
sips -z 64   64   "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_32x32@2x.png"     >/dev/null
sips -z 128  128  "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_128x128.png"      >/dev/null
sips -z 256  256  "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_128x128@2x.png"   >/dev/null
sips -z 256  256  "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_256x256.png"      >/dev/null
sips -z 512  512  "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_256x256@2x.png"   >/dev/null
sips -z 512  512  "$ICONSET/icon_512x512@2x.png" --out "$ICONSET/icon_512x512.png"      >/dev/null

iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICON_TMP"

# ─── Info.plist ─────────────────────────────────────────────────────────────
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Calbar</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>Calbar</string>
    <key>CFBundleDisplayName</key>
    <string>Calbar</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# ─── no OAuth client inside ─────────────────────────────────────────────────
LEAKED=$(find "$APP" -iname 'google-oauth*.json')
if [ -n "$LEAKED" ]; then
    echo "✗ OAuth client file inside $APP, refusing to package:"
    echo "$LEAKED"
    rm -rf "$APP"
    exit 1
fi

# Signing. An Apple Development certificate is preferred: it carries a team
# ID, and Keychain items remember the app by it ("teamid:" partition), so
# "Always Allow" lasts across builds. A self-signed certificate has no team
# ID: items remember the exact build ("cdhash:"), and each new build asks
# again, once per item. Without any identity, ad hoc signing.
DEV_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)
SIGN_IDENTITY="${CALBAR_SIGN_IDENTITY:-${DEV_IDENTITY:-Claudette Dev}}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
    echo "▶ Signing with \"$SIGN_IDENTITY\"…"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP" >/dev/null
else
    echo "▶ Ad hoc signing (no \"$SIGN_IDENTITY\" identity in the keychain)."
    codesign --force --deep --sign - "$APP" >/dev/null
fi

# Refreshes the icon cache so Finder shows the icon.
touch "$APP"

# Registers the bundle with LaunchServices. Without it UNUserNotificationCenter
# refuses notifications ("bundle proxy not found").
LSREG="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
[ -x "$LSREG" ] && "$LSREG" -f "$APP" 2>/dev/null || true

echo "✓ $APP ready."
echo "  Launch: open $(pwd)/$APP"

# ─── DMG (release artifact) ─────────────────────────────────────────────────
# A drag-and-drop Calbar.dmg: Calbar.app next to an Applications alias. Native
# hdiutil, no Homebrew dependency.
DMG="Calbar.dmg"
echo "▶ Packaging $DMG…"
rm -f "$DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
    -volname "Calbar" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null
rm -rf "$STAGE"
echo "✓ $DMG ready ($(du -h "$DMG" | cut -f1))."

# ─── Macal.dmg (transition from Macal) ──────────────────────────────────────
# Up to 0.2.9 the app was Macal: its updater downloads the release asset
# Macal.dmg, checks for an executable Macal.app/Contents/MacOS/Macal, and
# installs it in place of Macal.app. This DMG holds Calbar under that name,
# with a Macal symlink to the Calbar executable; launched from Macal.app,
# Calbar copies itself to Calbar.app and moves the old bundle to the Trash.
LEGACY_DMG="Macal.dmg"
echo "▶ Packaging $LEGACY_DMG (transition)…"
rm -f "$LEGACY_DMG"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/Macal.app"
ln -s Calbar "$STAGE/Macal.app/Contents/MacOS/Macal"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
    codesign --force --deep --sign "$SIGN_IDENTITY" "$STAGE/Macal.app" >/dev/null
else
    codesign --force --deep --sign - "$STAGE/Macal.app" >/dev/null
fi
hdiutil create \
    -volname "Calbar" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$LEGACY_DMG" >/dev/null
rm -rf "$STAGE"
echo "✓ $LEGACY_DMG ready ($(du -h "$LEGACY_DMG" | cut -f1))."

if [ "${1:-}" = "--install" ]; then
    echo "▶ Installing into /Applications…"
    rm -rf "/Applications/$APP"
    cp -R "$APP" "/Applications/"
    echo "✓ /Applications/$APP installed."
    echo "  Launch: open /Applications/$APP"
fi
