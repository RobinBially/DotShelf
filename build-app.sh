#!/bin/bash
set -euo pipefail

# Baut KonfigEditor.app als fertiges, doppelklickbares macOS-App-Bundle.
cd "$(dirname "$0")"

APP_NAME="Konfig-Editor"
BIN_NAME="KonfigEditor"
BUNDLE_ID="ai.robin.konfigeditor"
DEST="${1:-$HOME/Applications}"

echo "▸ Release-Build…"
# Bevorzugt SwiftPM. Ist das swift-package-Tool defekt (z. B. fehlendes
# BuildServerProtocol.framework in manchen CommandLineTools-Installationen),
# fällt der Build direkt auf swiftc zurück.
if swift build -c release 2>/dev/null; then
    BIN_PATH="$(swift build -c release --show-bin-path)/$BIN_NAME"
else
    echo "  ⚠ SwiftPM nicht verfügbar – Fallback auf direkten swiftc-Build"
    BIN_PATH=".build/manual/$BIN_NAME"
    mkdir -p .build/manual
    xcrun swiftc -O -swift-version 5 \
        -sdk "$(xcrun --show-sdk-path)" \
        -target arm64-apple-macosx14.0 \
        Sources/"$BIN_NAME"/*.swift \
        -o "$BIN_PATH"
fi

APP_DIR="$DEST/$APP_NAME.app"
echo "▸ App-Bundle erstellen: $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$BIN_NAME"

# Icon erzeugen
echo "▸ Icon erzeugen…"
ICONSET="$(mktemp -d)/KonfigEditor.iconset"
swift make-icon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

# Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$BIN_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

# Ad-hoc signieren, damit Gatekeeper die lokale App startet
echo "▸ Ad-hoc signieren…"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "✓ Fertig: $APP_DIR"
