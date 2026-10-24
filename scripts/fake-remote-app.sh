#!/bin/bash
# Builds and launches a harmless dummy app named "AnyDesk (Demo)" so the remote-access shield
# can be demoed and tested without a real remote-control program. It just shows a small window.
#   scripts/fake-remote-app.sh          build + launch
#   scripts/fake-remote-app.sh --build  build only
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/AnyDesk (Demo).app"
if [ ! -x "$APP/Contents/MacOS/FakeRemote" ]; then
  mkdir -p "$APP/Contents/MacOS" "$ROOT/.build/fake-remote"
  cat > "$ROOT/.build/fake-remote/main.swift" <<'SWIFT'
import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 220), styleMask: [.titled, .closable], backing: .buffered, defer: false)
w.title = "AnyDesk (Demo)"
let label = NSTextField(labelWithString: "DEMO ONLY — not a real remote-control app.\n\nYour address: 123 456 789\nWaiting for a connection…")
label.font = .systemFont(ofSize: 16)
label.frame = NSRect(x: 24, y: 40, width: 380, height: 140)
w.contentView?.addSubview(label)
w.center(); w.makeKeyAndOrderFront(nil)
app.run()
SWIFT
  O="$ROOT/.build/toolchain-fix/overlay.yaml"
  "$ROOT/scripts/swiftw" build >/dev/null 2>&1 || true   # makes sure the overlay exists
  FLAGS=(); [ -f "$O" ] && FLAGS=(-vfsoverlay "$O")
  swiftc "${FLAGS[@]}" -O "$ROOT/.build/fake-remote/main.swift" -o "$APP/Contents/MacOS/FakeRemote"
  cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>AnyDesk (Demo)</string>
<key>CFBundleIdentifier</key><string>com.lookout.demo.anydesk</string>
<key>CFBundleExecutable</key><string>FakeRemote</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
  codesign --force --sign - "$APP" >/dev/null 2>&1
fi
if [ "${1:-}" != "--build" ]; then open "$APP"; fi
echo "$APP"
