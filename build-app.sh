#!/bin/bash
set -euo pipefail

# Only a fully verified bundle replaces the installed app.
cd "$(dirname "$0")"
APP_NAME="DotShelf"
BIN_NAME="KonfigEditor"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
DEST="${1:-$HOME/Applications}"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION must be x.y.z." >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "BUILD_NUMBER must be a positive integer." >&2; exit 1; }
read -r -a architectures <<< "${ARCHS:-$(uname -m)}"
[[ ${#architectures[@]} -gt 0 ]] || { echo "ARCHS is empty." >&2; exit 1; }
for arch in "${architectures[@]}"; do
    [[ "$arch" == arm64 || "$arch" == x86_64 ]] || { echo "Unsupported architecture: $arch" >&2; exit 1; }
done

mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
STAGING="$(mktemp -d "$DEST/.DotShelf-build.XXXXXX")"
APP_DIR="$STAGING/$APP_NAME.app"
INSTALLED="$DEST/$APP_NAME.app"
cleanup() {
    local result=$?
    if [[ ( -e "$STAGING/previous.app" || -L "$STAGING/previous.app" ) && ! -e "$INSTALLED" && ! -L "$INSTALLED" ]]; then
        mv "$STAGING/previous.app" "$INSTALLED" || { echo "The previous app is preserved at $STAGING/previous.app" >&2; exit 1; }
    fi
    rm -rf "$STAGING"
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
binaries=()
resource_name="DotShelf_KonfigEditor.bundle"
resource_source=""
for arch in "${architectures[@]}"; do
    echo "▸ SwiftPM release build ($arch)…"
    scratch="$PWD/.build/bundle-$arch"
    swift build -c release --arch "$arch" --scratch-path "$scratch"
    bin_dir="$(swift build -c release --arch "$arch" --scratch-path "$scratch" --show-bin-path)"
    binaries+=("$bin_dir/$BIN_NAME")
    [[ -d "$bin_dir/$resource_name" ]] || {
        echo "Missing SwiftPM resource bundle: $bin_dir/$resource_name" >&2; exit 1;
    }
    if [[ -z "$resource_source" ]]; then
        resource_source="$bin_dir/$resource_name"
    else
        diff -qr "$resource_source" "$bin_dir/$resource_name" > /dev/null || {
            echo "Resource bundles differ between architectures." >&2; exit 1;
        }
    fi
done
if [[ ${#binaries[@]} -eq 1 ]]; then
    cp "${binaries[0]}" "$APP_DIR/Contents/MacOS/$BIN_NAME"
else
    xcrun lipo -create "${binaries[@]}" -output "$APP_DIR/Contents/MacOS/$BIN_NAME"
fi
for arch in "${architectures[@]}"; do
    xcrun lipo "$APP_DIR/Contents/MacOS/$BIN_NAME" -verify_arch "$arch"
done

# L10n resolves the embedded bundle here before using the SwiftPM fallback.
cp -R "$resource_source" "$APP_DIR/Contents/Resources/$resource_name"

echo "▸ Icon and bundle metadata…"
swift make-icon.swift "$STAGING/KonfigEditor.iconset" >/dev/null
iconutil -c icns "$STAGING/KonfigEditor.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$BIN_NAME</string>
    <key>CFBundleIdentifier</key><string>ai.robin.konfigeditor</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key><array><string>en</string></array>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict></plist>
PLIST
plutil -lint "$APP_DIR/Contents/Info.plist"

echo "▸ Sign and strictly verify…"
sign_options=(--force --sign "$CODE_SIGN_IDENTITY")
if [[ "$CODE_SIGN_IDENTITY" != - ]]; then
    sign_options+=(--options runtime --timestamp)
fi
if [[ -n "${CODE_SIGN_KEYCHAIN:-}" ]]; then
    sign_options+=(--keychain "$CODE_SIGN_KEYCHAIN")
fi
codesign "${sign_options[@]}" "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

if [[ -e "$INSTALLED" || -L "$INSTALLED" ]]; then
    mv "$INSTALLED" "$STAGING/previous.app"
fi
mv "$APP_DIR" "$INSTALLED"
echo "✓ Ready: $INSTALLED"
