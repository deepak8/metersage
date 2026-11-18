#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="$PWD/artifacts/MeterSage.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/MeterSage "$APP/Contents/MacOS/MeterSage"
# Existing Claude status-line commands may reference the former executable.
ln -sfn MeterSage "$APP/Contents/MacOS/UsageMonitor"
# Remove vendor files left by earlier local builds. Icons now load at runtime.
for ICON in codex claude antigravity; do
  rm -f "$APP/Contents/Resources/$ICON.icns"
done
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MeterSage</string>
<key>CFBundleIdentifier</key><string>dev.usagemonitor.mac</string>
<key>CFBundleName</key><string>MeterSage</string>
<key>CFBundleDisplayName</key><string>MeterSage</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
# Preserve the old local app path without deleting its previous build. The old
# executable alias above keeps an already-configured Claude bridge working.
LEGACY_APP="$PWD/artifacts/Usage Monitor.app"
if [[ -e "$LEGACY_APP" && ! -L "$LEGACY_APP" ]]; then
  LEGACY_BACKUP="$(mktemp -d "$PWD/artifacts/legacy-build.XXXXXX")"
  mv "$LEGACY_APP" "$LEGACY_BACKUP/Usage Monitor.app"
fi
ln -sfn MeterSage.app "$LEGACY_APP"
echo "Built: $APP"
