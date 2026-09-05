#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Only this explicit command submits an app to Apple for notarization.
: "${VERSION:?VERSION must be set (x.y.z)}"
: "${BUILD_NUMBER:?BUILD_NUMBER must be set}"
: "${CODE_SIGN_IDENTITY:?A Developer ID Application identity must be set}"
: "${NOTARY_PROFILE:?An existing notarytool keychain profile must be set}"
[[ "$CODE_SIGN_IDENTITY" == 'Developer ID Application: '* ]] || {
    echo "Releases require a Developer ID Application identity." >&2; exit 1;
}
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION must be x.y.z." >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "BUILD_NUMBER must be a positive integer." >&2; exit 1; }
# Explicit repository identity prevents a cask from pointing at a guessed release.
: "${RELEASE_REPOSITORY:?Set RELEASE_REPOSITORY to the GitHub owner/repository}"
[[ "$RELEASE_REPOSITORY" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$ ]] || {
    echo "RELEASE_REPOSITORY must be a GitHub owner/repository." >&2; exit 1;
}
OUTPUT="${1:-$PWD/.build/releases}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
ZIP_NAME="DotShelf-$VERSION.zip"
[[ ! -e "$OUTPUT/$ZIP_NAME" && ! -e "$OUTPUT/$ZIP_NAME.sha256" ]] || {
    echo "Release artifact already exists: $OUTPUT/$ZIP_NAME" >&2; exit 1;
}
WORK="$(mktemp -d "$OUTPUT/.release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ARCHS="${ARCHS:-arm64 x86_64}" ./build-app.sh "$WORK"
APP="$WORK/DotShelf.app"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/submission.zip"
notary_options=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
    notary_options+=(--keychain "$NOTARY_KEYCHAIN")
fi
if ! xcrun notarytool submit "$WORK/submission.zip" "${notary_options[@]}" --wait --timeout 30m --output-format json > "$WORK/notary.json"; then
    cat "$WORK/notary.json" >&2
    echo "Notarization failed; no release artifact created." >&2
    exit 1
fi
if [[ "$(plutil -extract status raw -o - "$WORK/notary.json")" != Accepted ]]; then
    cat "$WORK/notary.json" >&2
    echo "Notarization was not accepted; no release artifact created." >&2
    exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"
# The final ZIP contains the stapled notarization ticket.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/$ZIP_NAME"
(cd "$WORK" && shasum -a 256 "$ZIP_NAME" > "$ZIP_NAME.sha256")
python3 scripts/generate-cask.py --version "$VERSION" --repository "$RELEASE_REPOSITORY" \
    --archive "$WORK/$ZIP_NAME" --output "$WORK/dotshelf.rb"
mkdir -p "$OUTPUT/Casks"
mv "$WORK/$ZIP_NAME" "$WORK/$ZIP_NAME.sha256" "$OUTPUT/"
# This is the cask for the latest locally generated release; ZIPs remain immutable.
mv "$WORK/dotshelf.rb" "$OUTPUT/Casks/dotshelf.rb"
echo "✓ Notarized release: $OUTPUT/$ZIP_NAME"
