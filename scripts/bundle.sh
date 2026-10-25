#!/bin/bash
# Build Scout.app (release) into build/Scout.app and sign it.
# Signs with the "Lookout Dev" identity if present (stable → macOS keeps granted permissions across rebuilds),
# otherwise ad-hoc (permissions must be re-granted after each rebuild). Create the identity once with
# scripts/make-signing-identity.sh.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIG="${CONFIG:-release}"
"$ROOT/scripts/swiftw" build -c "$CONFIG" --product Lookout
BIN="$(swift build -c "$CONFIG" --show-bin-path 2>/dev/null || echo "$ROOT/.build/$CONFIG")/Lookout"
[ -x "$BIN" ] || BIN="$ROOT/.build/arm64-apple-macosx/$CONFIG/Lookout"
APP="$ROOT/build/Scout.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Scout"
rsync -a --exclude ".DS_Store" "$ROOT/demo" "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/model" && cp "$ROOT/model/playbooks.json" "$APP/Contents/Resources/model/"
# Buddy drawings (scripts/gen-sprites.py); the large previews stay out of the app.
[ -d "$ROOT/Resources/sprites" ] && rsync -a --exclude "*@preview.png" --exclude ".DS_Store" "$ROOT/Resources/sprites" "$APP/Contents/Resources/"
# App icon, drawn by the app itself (AppIconView).
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
"$BIN" --render-icon "$ICONSET/base.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
rm "$ICONSET/base.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
VERSION="0.1.$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Scout</string>
  <key>CFBundleDisplayName</key><string>Scout</string>
  <key>CFBundleIdentifier</key><string>com.scout.companion</string>
  <key>CFBundleExecutable</key><string>Scout</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><false/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Scout listens while you hold your talk keys, so you can ask for help out loud.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Scout turns your spoken question into text so it can help you.</string>
  <key>NSAppleEventsUsageDescription</key><string>Scout can close a dangerous window for you when you ask.</string>
  <key>NSScreenCaptureUsageDescription</key><string>Scout looks at your screen to spot scams and show you where to click.</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST
xattr -cr "$APP"
IDENTITY="${LOOKOUT_SIGN_IDENTITY:-Lookout Dev}"
# Fall back to an Xcode "Apple Development" certificate if there is one (also stable across rebuilds).
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
  DEV="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
  [ -n "$DEV" ] && IDENTITY="$DEV"
fi
if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
  # No hardened runtime: it would block the microphone without extra entitlements, and we don't notarize.
  sign() { codesign --force --deep --sign "$IDENTITY" "$APP"; }
  echo "Signing with stable identity '$IDENTITY'."
else
  sign() { codesign --force --deep --sign - "$APP"; }
  echo "Signing ad-hoc (no '$IDENTITY' identity). Permissions must be re-granted after each rebuild."
  echo "Run scripts/make-signing-identity.sh once to fix that."
fi
# macOS sometimes re-adds Finder metadata between xattr and codesign; retry a few times.
for i in 1 2 3; do xattr -cr "$APP"; if sign 2>/dev/null; then break; fi; sleep 1; done
codesign --verify --verbose=1 "$APP" 2>&1 | tail -1
echo "Built $APP"
