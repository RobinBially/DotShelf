# DotShelf release review

Updated September 5, 2026. Original review baseline: the original KonfigEditor app.

The initial review found eight release blockers. They have been addressed in the
DotShelf source, alongside English localization and the distribution
pipeline. A packaged release, Apple notarization and a second-machine download test
remain separate release gates.

## Original findings and resolution

| ID | Original problem | Current resolution |
|---|---|---|
| R1 | JSONC formatting changed comma/bracket sequences inside strings. | A lexical scanner preserves string and escape contents; regression cases include Unicode and URLs. |
| R2 | Formatting scalar JSON such as `true` terminated the app. | Both reading and writing allow JSON fragments; scalar formatting is tested. |
| R3 | Reload, add/create and remove could discard edits without asking. | A shared Save/Discard/Cancel guard protects every transition. |
| R4 | “Save and switch” switched even after a failed save. | Save returns success/failure; failed saves retain the buffer, selection and error. |
| R5 | Closing or quitting did not protect unsaved edits. | A single-window lifecycle integrates the same guard into close and quit, with no duplicate prompt after an approved close. |
| R6 | Atomic writes replaced symlinks and could change permissions. | Resolve and verify the actual destination, retain metadata and the link, stage on the destination filesystem, then replace the target. Backups contain independent file contents. |
| R7 | External edits were silently overwritten. | Compare the loaded file snapshot, target identity and contents before saving. Conflicts stop the save and retain edits. |
| R8 | Renaming a missing source could adopt and overwrite an existing target. | Check source and target separately, reject collisions and missing sources, and preserve the loaded baseline across a successful move. |
| G1 | JSON validation did not update during typing. | Text changes update validation immediately. |
| G2 | Strict JSON accepted comments, trailing commas and empty input. | JSON and JSONC are parsed separately; invalid strict JSON is rejected by validation. Saving invalid text remains an intentional supported operation. |
| G3 | CRLF comments swallowed subsequent content. | Scan Unicode scalars, preserve line endings and reject unterminated block comments. |
| G4 | Two saves in a second overwrote the first backup. | Unique UUID-backed backup names; existing backups are never deleted during a save. |
| G5 | No automated regression tests. | XCTest covers JSON, file protection, Store transitions, lifecycle and localization. |
| G6 | JSONC URLs were colored as comments. | Comment matching skips quoted strings; string/comment colors have a regression test. |
| G7 | Failed empty-file creation still reported success. | Create with private permissions, check the result and mutate the sidebar only after success. |

Conflict detection is optimistic: an unrelated process writing at precisely the
final rename instant is not coordinated by an OS-level compare-and-swap. ACLs,
network filesystems and large-file performance have not been exhaustively tested.

## English and branding

- Product, app bundle and release archives are named **DotShelf**.
- English is the development language and the only currently shipped UI language.
- Menus, prompts, labels, help and status messages use `L10n` and an English string table.
- CI checks that the table contains every source key. Resources are packaged inside
  the app and resolve after the app is moved outside the build directory.
- The internal executable/module and existing bundle ID remain unchanged so user
  settings survive the rename. The old app bundle is not silently deleted.

## Distribution

- Initial GitHub state: private repository, no workflows, tags, releases or license.
- Prepared CI builds and tests; the manual release workflow produces a notarized
  Universal app, checksum and Homebrew cask as a **draft**.
- Signing-secret names match Locomni: `CSC_LINK`, `CSC_KEY_PASSWORD`, `APPLE_ID`,
  `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`. Secrets were not copied or exported.
- The new `localfoundry/homebrew-tap` is public and contains search-rotation; DotShelf remains pending its public notarized release. The generated cask needs to be
  committed there after the release is available; the public install command will
  be `brew install --cask localfoundry/tap/dotshelf`.
- The source repository is public under `RobinBially/DotShelf`. Packaged releases remain pending.

## Verification

Tests use temporary synthetic files and isolated preferences, never private
configuration files. The final XCTest run passed **27 tests with zero failures** using full Xcode.
The local **0.1.0 Universal candidate** is Developer-ID signed with Hardened
Runtime and a secure timestamp; strict signature verification passes. Apple
notarization is still pending because no local notary credentials/profile was available.

- XCTest suite under full Xcode, plus English-catalog and shell/YAML checks.
- Native app packaging, embedded resource relocation and architecture verification.
- Release failure paths and cask generation exercised with synthetic mock artifacts:
  failed signing keeps the existing installation; rejected notarization creates no release.
- Native demo-window checks confirmed English menus/prompts, immediate invalid-JSON
  feedback, Cancel preserving edits for both Quit and window Close, and confirmed
  discard before Reload. The updated screenshot uses the actual views with example data.

## Remaining release gates

1. Finish Apple notarization of the final candidate and verify its stapled ticket.
2. Test the downloaded app with Gatekeeper on a second Mac, including Intel and the
   minimum supported macOS version where hardware is available.
3. Publish the verified app release, then commit the generated cask to the public LocalFoundry tap.
4. Run the remote workflows with the configured Apple credentials.

Future features are tracked in the [roadmap](ROADMAP.md), and operational details
in the [release guide](RELEASING.md).
