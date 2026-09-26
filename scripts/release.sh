#!/bin/bash
# Release DotShelf: checks, build, sign, notarize — and publish on request.
#
# Usage:
#   VERSION=1.0.1 ./scripts/release.sh [output-dir] [--dry-run] [--publish] [--draft] [--force]
#
# Without --publish the script only writes the local artifacts: the notarized
# ZIP, its SHA-256 and the Homebrew cask into the output directory
# (.build/releases by default). --publish additionally creates the GitHub release
# and updates the cask in robin-bially/homebrew-tap. --dry-run checks the
# prerequisites without building; --force tolerates a dirty working tree.
#
# Environment:
#   VERSION             required, x.y.z
#   BUILD_NUMBER        default: commit count of this checkout
#   CODE_SIGN_IDENTITY  default: first Developer ID identity in the keychain
#   NOTARY_PROFILE      default: notarization.keychain_profile from
#                       ~/.config/macos-sign-release/config.json
#   RELEASE_REPOSITORY  default robin-bially/DotShelf
#   TAP_REPOSITORY      default robin-bially/homebrew-tap
#   TAP_DIR             existing tap checkout; otherwise cloned temporarily
#   SKIP_AUDIT=1        skip the online brew audit after the tap push
#
# The script is self-contained: it needs git, gh, python3, Xcode and an
# authenticated notarytool profile. The only file outside this repository is
# the tap, which it clones when no checkout is given.
set -euo pipefail
cd "$(dirname "$0")/.."

for arg in "$@"; do
    case "$arg" in
        -h|--help) sed -n '2,24p' "$0" | sed 's/^# *//'; exit 0 ;;
    esac
done

# Only this explicit command submits an app to Apple for notarization.
VERSION="${VERSION:?VERSION must be set (x.y.z)}"
RELEASE_REPOSITORY="${RELEASE_REPOSITORY:-robin-bially/DotShelf}"
TAP_REPOSITORY="${TAP_REPOSITORY:-robin-bially/homebrew-tap}"
TAP_FORMULA="dotshelf"
ARCHIVE="DotShelf-$VERSION.zip"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION must be x.y.z, got: $VERSION" >&2; exit 1; }
[[ "$RELEASE_REPOSITORY" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$ ]] || { echo "RELEASE_REPOSITORY must be owner/repo." >&2; exit 1; }

out=""
dry_run=0 publish=0 draft=0 force=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) dry_run=1; shift ;;
        --publish) publish=1; shift ;;
        --draft) draft=1; shift ;;
        --force) force=1; shift ;;
        -h|--help) sed -n '2,24p' "$0" | sed 's/^# *//'; exit 0 ;;
        -*) echo "Unknown argument: $1" >&2; exit 1 ;;
        *) out="$1"; shift ;;
    esac
done
OUTPUT="${out:-$PWD/.build/releases}"
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"

BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"
SIGN_CONFIG="${SIGN_CONFIG:-$HOME/.config/macos-sign-release/config.json}"
NOTARY_PROFILE="${NOTARY_PROFILE:-$(plutil -extract notarization.keychain_profile raw -o - "$SIGN_CONFIG" 2>/dev/null || true)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-localfoundry-notary}"
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "BUILD_NUMBER must be a positive integer, got: $BUILD_NUMBER" >&2; exit 1; }
if [[ -z "${CODE_SIGN_IDENTITY:-}" ]]; then
    CODE_SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi

cleanup_tap=""
cleanup() { if [[ -n "$cleanup_tap" ]]; then rm -rf "$cleanup_tap"; fi; }
trap cleanup EXIT

# --- Voraussetzungen ---------------------------------------------------------
issues=()
command -v git >/dev/null || issues+=("git fehlt.")
command -v gh >/dev/null || issues+=("gh CLI fehlt.")
command -v python3 >/dev/null || issues+=("python3 fehlt.")
[[ -n "$CODE_SIGN_IDENTITY" ]] || issues+=("Keine Developer-ID-Application-Identität im Schlüsselbund gefunden.")
if [[ -n "$CODE_SIGN_IDENTITY" && "$CODE_SIGN_IDENTITY" != 'Developer ID Application: '* ]]; then
    issues+=("CODE_SIGN_IDENTITY ist keine Developer ID Application identity: $CODE_SIGN_IDENTITY")
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    issues+=("Notary-Profil \"$NOTARY_PROFILE\" nicht nutzbar. Einmalig: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <apple-id> --team-id 7JGZFDP3FA")
fi
if [[ $force -eq 0 ]]; then
    git diff --quiet || issues+=("Uncommitted changes; erst committen (--force überspringt).")
    [[ -z "$(git ls-files --others --exclude-standard)" ]] || issues+=("Untracked files; erst committen oder ignorieren (--force überspringt).")
fi
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null && issues+=("Tag v$VERSION existiert lokal schon.")
git ls-remote --exit-code --tags origin "refs/tags/v$VERSION" >/dev/null 2>&1 && issues+=("Tag v$VERSION ist im Remote schon vorhanden.")
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [[ -n "$upstream" ]]; then
    git fetch --quiet origin || issues+=("git fetch origin ist fehlgeschlagen.")
    behind="$(git rev-list --count "HEAD..$upstream" 2>/dev/null || echo 0)"
    [[ "$behind" == 0 ]] || issues+=("$behind Commit(s) fehlen lokal gegenüber $upstream; erst pullen.")
fi
[[ ! -e "$OUTPUT/$ARCHIVE" && ! -e "$OUTPUT/$ARCHIVE.sha256" ]] || issues+=("Release artifact already exists: $OUTPUT/$ARCHIVE")

if [[ ${#issues[@]} -gt 0 ]]; then
    echo "Voraussetzungen nicht erfüllt:" >&2
    printf "  - %s\n" "${issues[@]}" >&2
    exit 1
fi

echo "== DotShelf $VERSION (Build $BUILD_NUMBER)"
echo "   Repository $RELEASE_REPOSITORY"
echo "   Identität  $CODE_SIGN_IDENTITY"
echo "   Notary     $NOTARY_PROFILE"
echo "   Ausgabe    $OUTPUT"
if [[ $publish -eq 1 ]]; then echo "   Modus      veröffentlichen"; else echo "   Modus      nur Artefakte (--publish veröffentlicht)"; fi

if [[ $dry_run -eq 1 ]]; then
    echo "== Probelauf: Voraussetzungen erfüllt, nichts gebaut."
    exit 0
fi

# --- Checks ------------------------------------------------------------------
# XCTest und das SwiftUI-Macro-Plugin kommen nur mit dem vollen Xcode; die
# Command Line Tools allein reichen nicht (siehe docs/RELEASING.md).
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p)" == /Library/Developer/CommandLineTools ]]; then
    for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        if [[ -d "$candidate/Contents/Developer" ]]; then
            export DEVELOPER_DIR="$candidate/Contents/Developer"
            echo "   Toolchain $DEVELOPER_DIR"
            break
        fi
    done
fi

echo "== Checks"
python3 scripts/check-localization.py
swift test

# --- Bauen, signieren, notarisieren ------------------------------------------
echo "== Bauen, signieren, notarisieren"
SOURCE_COMMIT="$(git rev-parse HEAD)"
WORK="$(mktemp -d "$OUTPUT/.release.XXXXXX")"
trap 'cleanup; rm -rf "$WORK"' EXIT
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
ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/$ARCHIVE"
(cd "$WORK" && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
python3 scripts/generate-cask.py --version "$VERSION" --repository "$RELEASE_REPOSITORY" \
    --archive "$WORK/$ARCHIVE" --output "$WORK/dotshelf.rb"
mkdir -p "$OUTPUT/Casks"
mv "$WORK/$ARCHIVE" "$WORK/$ARCHIVE.sha256" "$OUTPUT/"
# This is the cask for the latest locally generated release; ZIPs remain immutable.
mv "$WORK/dotshelf.rb" "$OUTPUT/Casks/$TAP_FORMULA.rb"
echo "✓ Notarized release: $OUTPUT/$ARCHIVE"

if [[ $publish -eq 0 ]]; then
    cat <<EOF
== Fertig (nur Artefakte)
   ZIP      $OUTPUT/$ARCHIVE
   Cask     $OUTPUT/Casks/$TAP_FORMULA.rb
   Zum Veröffentlichen erneut mit --publish starten.
EOF
    exit 0
fi

# --- Veröffentlichen ---------------------------------------------------------
echo "== Commit pushen"
git push origin HEAD

echo "== GitHub-Release"
release_args=("v$VERSION" "$OUTPUT/$ARCHIVE" "$OUTPUT/$ARCHIVE.sha256" "$OUTPUT/Casks/$TAP_FORMULA.rb"
              --repo "$RELEASE_REPOSITORY" --target "$SOURCE_COMMIT" --title "DotShelf $VERSION" --generate-notes)
if [[ $draft -eq 1 ]]; then
    release_args+=(--draft)
fi
# GitHub erzeugt die Notizen serverseitig; der Aufruf kann mit HTTP 500
# scheitern, ohne dass ein Release entsteht. Dann mit lokaler Notiz erneut.
if ! gh release create "${release_args[@]}"; then
    echo "   Notizen-Erzeugung fehlgeschlagen; erneut mit lokaler Notiz." >&2
    fallback_args=()
    for arg in "${release_args[@]}"; do
        if [[ "$arg" == "--generate-notes" ]]; then continue; fi
        fallback_args+=("$arg")
    done
    gh release create "${fallback_args[@]}" --notes "Release $VERSION"
fi

echo "== Homebrew-Tap"
if [[ -n "${TAP_DIR:-}" && -d "${TAP_DIR}/.git" ]]; then
    tap="$TAP_DIR"
else
    cleanup_tap="$(mktemp -d)"
    git clone --quiet --depth=1 "https://github.com/$TAP_REPOSITORY.git" "$cleanup_tap"
    tap="$cleanup_tap"
fi
formula_path="$tap/Casks/$TAP_FORMULA.rb"
[[ -f "$formula_path" ]] || { echo "Cask fehlt: $formula_path" >&2; exit 1; }
python3 - "$VERSION" "$OUTPUT/Casks/$TAP_FORMULA.rb" "$formula_path" <<'PYTHON'
import re, sys
from pathlib import Path
incoming = tuple(map(int, sys.argv[1].split(".")))
generated, target = Path(sys.argv[2]), Path(sys.argv[3])
if target.exists():
    old = target.read_text()
    match = re.search(r'version "([0-9]+\.[0-9]+\.[0-9]+)"', old)
    if not match:
        raise SystemExit("Existing cask has no readable version; aborting.")
    previous = tuple(map(int, match[1].split(".")))
    if previous > incoming:
        raise SystemExit("Tap already has a newer version; no downgrade.")
    if previous == incoming:
        new = generated.read_text()
        for field in ("sha256", "url"):
            pattern = field + r' "([^"\n]+)"'
            if re.search(pattern, old).group(1) != re.search(pattern, new).group(1):
                raise SystemExit("Same version, different release bytes or URL; aborting.")
PYTHON
cp "$OUTPUT/Casks/$TAP_FORMULA.rb" "$formula_path"
git -C "$tap" add "Casks/$TAP_FORMULA.rb"
if git -C "$tap" diff --cached --quiet; then
    echo "   Cask unverändert."
else
    git -C "$tap" commit -q -m "Release DotShelf $VERSION"
    git -C "$tap" push origin HEAD
    echo "   Cask gepusht."
    if [[ $draft -eq 1 ]]; then
        echo "   Entwurf: Online-Audit erst nach dem Veröffentlichen des Releases."
    elif [[ "${SKIP_AUDIT:-0}" != 1 ]] && command -v brew >/dev/null; then
        brew update -q
        brew audit --cask --strict --online "robin-bially/tap/$TAP_FORMULA"
    fi
fi

cat <<EOF
== Fertig
   Release  https://github.com/$RELEASE_REPOSITORY/releases/tag/v$VERSION
   ZIP      $ARCHIVE
   Cask     $formula_path
   Quelle   $SOURCE_COMMIT, Build $BUILD_NUMBER
EOF
