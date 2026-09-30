#!/bin/bash
# Build MCClose, install it to /Applications, and keep it running via a LaunchAgent.
set -euo pipefail

cd "$(dirname "$0")/.."
APP_NAME="MCClose"
BUNDLE_ID="com.joseph.mcclose"
APP="/Applications/$APP_NAME.app"
AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
VERSION="1.0.$(date +%Y%m%d%H%M)"

# A stable (non ad-hoc) signature keeps the Accessibility grant across rebuilds.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/Apple Development|Developer ID Application/ {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"

echo "==> Building"
swift build -c release --quiet
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "==> Assembling bundle"
STAGE="build/$APP_NAME.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BIN" "$STAGE/Contents/MacOS/$APP_NAME"
cat > "$STAGE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>MCClose</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF

echo "==> Signing with identity $IDENTITY"
codesign --force --options runtime --timestamp=none --identifier "$BUNDLE_ID" --sign "$IDENTITY" "$STAGE"
codesign --verify --strict "$STAGE"

echo "==> Installing to $APP"
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
rm -rf "$APP"
cp -R "$STAGE" "$APP"

echo "==> Registering LaunchAgent (starts at login, restarts if it crashes)"
mkdir -p "$(dirname "$AGENT")"
cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$BUNDLE_ID</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/$APP_NAME</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
  <key>ThrottleInterval</key><integer>10</integer>
</dict></plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$AGENT"

echo "==> Done. If prompted, enable MCClose under System Settings → Privacy & Security → Accessibility."
