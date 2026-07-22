#!/bin/sh
# Build and install "Herdr Notify.app" into ~/Applications.
#
#   ./build.sh          rebuild with the current icon emoji
#   ./build.sh 🐕       rebuild with a different emoji
#
set -eu

EMOJI="${1:-🐑}"
SRC="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/Herdr Notify.app"
BUILD="$SRC/.build"

rm -rf "$BUILD"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> compiling notifier"
swiftc -O -o "$BUILD/herdr-notify" "$SRC/main.swift" \
    -framework UserNotifications -framework AppKit

echo "==> rendering $EMOJI icon"
swiftc -O -o "$BUILD/makeicon" "$SRC/makeicon.swift" -framework AppKit
"$BUILD/makeicon" "$EMOJI" "$BUILD/AppIcon.iconset"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUILD/AppIcon.icns"

echo "==> installing to $APP"
cp "$BUILD/herdr-notify" "$APP/Contents/MacOS/herdr-notify"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Herdr</string>
  <key>CFBundleDisplayName</key><string>Herdr</string>
  <key>CFBundleExecutable</key><string>herdr-notify</string>
  <key>CFBundleIdentifier</key><string>dev.herdr.notify</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - --identifier dev.herdr.notify "$APP"
codesign -v "$APP"

# Registering with LaunchServices makes macOS pick up a changed icon sooner. It's a
# nicety, not a requirement, and it isn't meaningful on a CI runner — never fail on it.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP" || true

echo "==> done. test with:  herdr notification show \"test\" --body \"hello\""
echo "    (if the icon looks stale, run: killall usernoted)"
