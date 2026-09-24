# Building and releasing DotShelf

Requires macOS with Xcode 26.3 and its command-line tools selected. DotShelf runs on macOS 14 and later; the macOS 26 SDK is needed to compile the conditional toolbar APIs. Releases are built and published locally; no CI job signs, notarizes or uploads anything. When `xcode-select` points at the standalone Command Line Tools, `scripts/release.sh` switches `DEVELOPER_DIR` to an installed Xcode, because only the full toolchain provides XCTest for `swift test`.

## Local builds

```bash
./build-app.sh .build/local
ARCHS="arm64 x86_64" VERSION=1.0.0 BUILD_NUMBER=1 ./build-app.sh .build/universal
```

Without a destination argument, the script installs `~/Applications/DotShelf.app`. By default it builds the host architecture and signs ad hoc. The complete staged bundle is verified before replacing an existing DotShelf installation. A failed build preserves the previous installation. There is no direct `swiftc` fallback.

The executable and SwiftPM target remain `KonfigEditor`; the bundle identifier remains `ai.robin.konfigeditor` so existing preferences are retained. The SwiftPM resource bundle, `DotShelf_KonfigEditor.bundle`, is copied into `Contents/Resources`. Both the application and resource bundle use English as the development language. The application resolves its embedded resource bundle before falling back to SwiftPM's resolver for command-line development.

| Variable | Default / meaning |
| --- | --- |
| `VERSION` | `1.0.0`; three numeric components `x.y.z` |
| `BUILD_NUMBER` | `1`; positive integer for `CFBundleVersion` |
| `ARCHS` | Host architecture; use `arm64 x86_64` for Universal |
| `CODE_SIGN_IDENTITY` | `-` for ad hoc; a Developer ID Application identity enables Hardened Runtime and secure timestamps |
| `CODE_SIGN_KEYCHAIN` | Optional keychain containing the signing key |

An ad-hoc signature is intended for local development. Distribution uses Developer ID signing and notarization through the release script below.

## Create a notarized release ZIP

A Developer ID Application certificate with its private key and an existing `notarytool` keychain profile are required. Set up a profile interactively with `xcrun notarytool store-credentials PROFILE_NAME`. Keep credentials out of the repository.

```bash
VERSION=1.0.0 ./scripts/release.sh              # build the notarized artifacts
VERSION=1.0.0 ./scripts/release.sh --publish    # also publish release and cask
```

`BUILD_NUMBER` defaults to the commit count, `CODE_SIGN_IDENTITY` to the first Developer ID identity in the keychain, `NOTARY_PROFILE` to `localfoundry-notary` and `RELEASE_REPOSITORY` to `RobinBially/DotShelf`; set them explicitly on another machine or for another team. `--dry-run` checks the prerequisites without building, `--force` tolerates a dirty working tree and `--draft` creates the GitHub release as a draft.

This explicit command builds Universal (`arm64 x86_64`) by default and submits the app to Apple. `NOTARY_KEYCHAIN` selects an optional keychain for the profile. Local callers can override `ARCHS`.

Only after Apple returns `Accepted`, stapling succeeds, and signature and Gatekeeper checks pass does the script produce:

- `DotShelf-VERSION.zip`, containing the app with its stapled notarization ticket.
- `DotShelf-VERSION.zip.sha256`, calculated from that final archive.
- `Casks/dotshelf.rb`, containing that version, its real archive SHA-256, and the matching GitHub release URL.

Existing ZIP and checksum files are never overwritten. The local cask represents the latest generated release and is replaced when another version is generated. `RELEASE_REPOSITORY` must identify the repository that will host the release; it is explicit to avoid guessing a URL after a repository rename. The source repository is `RobinBially/DotShelf`, on the developer’s personal profile.

Without `--publish` the script writes those artifacts and stops. With `--publish` it creates the GitHub release for the tagged commit and copies `Casks/dotshelf.rb` into `localfoundry/homebrew-tap` — cloned temporarily when `TAP_DIR` is not a checkout — refusing a downgrade or a same-version cask with different bytes, then runs `brew audit --cask --strict --online`. `SKIP_AUDIT=1` skips that audit. The cask generator does not independently notarize or attest an arbitrary archive; `release.sh` invokes it only after the verification above.

## Publishing a release

Releases run locally and from this checkout alone:

```bash
VERSION=1.0.1 ./scripts/release.sh --publish
```

The shared driver `~/.agents/skills/macos-sign-release/scripts/release.sh --project dotshelf --version x.y.z` is a convenience wrapper: it checks the prerequisites, resolves the signing identity, team ID and notary profile from `~/.config/macos-sign-release/config.json`, and then calls this same script with `--publish`.

Add `--dry-run` to check the prerequisites without building anything. The script requires a clean working tree (unless `--force`), a free version tag locally and remotely, and a usable notary profile; it runs the localization check and `swift test` before it builds. Missing credentials, a failed test or an existing version tag stop the release before anything is published. No signing secret lives in GitHub.

For manual verification, download the published ZIP, check its checksum and launch the app on Apple Silicon and Intel. A successful local build alone does not prove that the notarization ticket is stapled or that the Intel slice runs.


## Homebrew installation

DotShelf is available from the public [`localfoundry/homebrew-tap`](https://github.com/localfoundry/homebrew-tap):

```sh
brew install --cask localfoundry/tap/dotshelf
brew update
brew upgrade --cask dotshelf
```

For each update, publish the verified release first, then copy its generated
`Casks/dotshelf.rb` into the tap. Review the version, public URL and SHA-256.
Run `brew style localfoundry/tap/dotshelf` and
`brew audit --cask --strict --online localfoundry/tap/dotshelf`, then perform a real install.
The tap CI also installs the app and verifies its signature, stapled ticket and both architectures.

Never publish a placeholder checksum or a cask pointing at an unpublished draft.

## First release and future credentials

Version 0.1.0 was built from a fixed DotShelf source commit in a dedicated GitHub
Actions signing job using the maintainer's existing Apple signing secrets.
The secrets stayed in their existing repository; only the notarized ZIP, checksum
and generated cask were downloaded for publication here.

The standalone DotShelf release workflow still requires the secrets listed above
to be configured in this repository before it can publish subsequent draft releases.
The local `release.sh` path is also available with a local notarytool profile.
