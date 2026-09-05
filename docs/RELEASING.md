# Building and releasing DotShelf

Requires macOS with Xcode 26.3 and its command-line tools selected. DotShelf runs on macOS 14 and later; the macOS 26 SDK is needed to compile the conditional toolbar APIs. GitHub Actions uses `macos-15` and Xcode 26.3. Actions are pinned to commit SHAs.

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
VERSION=1.0.0 BUILD_NUMBER=1 \
CODE_SIGN_IDENTITY='Developer ID Application: NAME (TEAMID)' \
NOTARY_PROFILE='PROFILE_NAME' \
RELEASE_REPOSITORY='RobinBially/DotShelf' \
./scripts/release.sh .build/releases
```

This explicit command builds Universal (`arm64 x86_64`) by default and submits the app to Apple. `NOTARY_KEYCHAIN` selects an optional keychain for the profile. Local callers can override `ARCHS`; the GitHub release workflow always builds Universal.

Only after Apple returns `Accepted`, stapling succeeds, and signature and Gatekeeper checks pass does the script produce:

- `DotShelf-VERSION.zip`, containing the app with its stapled notarization ticket.
- `DotShelf-VERSION.zip.sha256`, calculated from that final archive.
- `Casks/dotshelf.rb`, containing that version, its real archive SHA-256, and the matching GitHub release URL.

Existing ZIP and checksum files are never overwritten. The local cask represents the latest generated release and is replaced when another version is generated. `RELEASE_REPOSITORY` must identify the repository that will host the release; it is explicit to avoid guessing a URL after a repository rename. The source repository is `RobinBially/DotShelf`, on the developer’s personal profile.

The script creates local artifacts only. It does not publish a GitHub release or update a Homebrew tap. The cask generator does not independently notarize or attest an arbitrary archive; `release.sh` invokes it only after the verification above.

## GitHub Actions and signing secrets

`ci.yml` runs `swift test`, builds and verifies a native ad-hoc app bundle, and uploads a ZIP as a workflow artifact.

`release.yml` runs only through `workflow_dispatch`, with a version in `x.y.z` format. It runs tests before importing signing material. The secret names follow the existing Locomni workflow:

| Secret | Content |
| --- | --- |
| `CSC_LINK` | Base64-encoded PKCS#12 export of the Developer ID Application certificate and private key; this workflow expects the base64 form, not a URL |
| `CSC_KEY_PASSWORD` | Nonempty password for the PKCS#12 export |
| `APPLE_ID` | Apple ID used for notarization |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password for that Apple ID |
| `APPLE_TEAM_ID` | Apple Developer team ID |

Configure these secrets separately for this repository or grant it access through organization secrets. No credentials are copied from Locomni by the build scripts. The workflow selects the single valid Developer ID Application identity imported for `APPLE_TEAM_ID`; no separate identity-name secret is needed. Missing secrets, ambiguous identities, an existing version tag, or a failed tag lookup stop the release. The certificate and notary profile live in a temporary keychain that is removed in an unconditional cleanup step.

The workflow builds both architectures, notarizes and verifies the app, then creates a **GitHub draft release** for the selected commit with the ZIP, checksum, and `dotshelf.rb` as assets. The build number is `github.run_number`, and the tag is `vVERSION`. Existing releases are not overwritten. Creating a draft does not make it available through the cask's public download URL.

Before publishing, download the draft artifact, check the checksum and app launch on Apple Silicon and Intel, and review the generated cask. A successful local build does not establish that remote signing, notarization, or Intel execution has passed.

## Homebrew installation

The public distribution tap is [`localfoundry/homebrew-tap`](https://github.com/localfoundry/homebrew-tap). It currently contains the search-rotation formula. DotShelf is still pending a public notarized release; the old personal tap is unrelated and is not used for new packages.
After the verified release has been published, copy its generated `Casks/dotshelf.rb` into that tap, review the version, URL and SHA-256, and commit it there. Do not commit a placeholder checksum or a cask pointing at an unpublished draft. Validate the cask in the tap with Homebrew's available style/audit checks and perform a real install.

Once those publication steps are complete, the intended installation command is:

```bash
brew install --cask localfoundry/tap/dotshelf
```

This command is a release target, not a claim that the cask is available today. The tap is public. Publishing the DotShelf release and committing its generated cask are still pending.
