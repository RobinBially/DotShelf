# DotShelf release review

Updated September 5, 2026. Original review baseline: the original KonfigEditor app.

The initial review found eight release blockers. They have been addressed in the
DotShelf source, alongside English localization and the distribution
pipeline. Version 0.1.0 is available as a signed, notarized Universal app and a Homebrew cask.

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

- The source repository is public under `RobinBially/DotShelf`.
- Version 0.1.0 ships as a Developer-ID-signed, notarized Universal ZIP with a
  stapled ticket and SHA-256 checksum.
- `localfoundry/homebrew-tap` contains the generated DotShelf cask:
  `brew install --cask localfoundry/tap/dotshelf`.
- CI builds and tests; the manual release workflow can produce notarized Universal
  builds as drafts once its signing secrets have been configured.

## Verification

Tests use temporary synthetic files and isolated preferences, never private
configuration files. The final XCTest run passed **27 tests with zero failures** using full Xcode.
The **0.1.0 Universal release** is Developer-ID signed with Hardened Runtime and
a secure timestamp. Apple notarization, stapling, strict signature verification
and Gatekeeper assessment pass. The published archive is verified by SHA-256.

- XCTest suite under full Xcode, plus English-catalog and shell/YAML checks.
- Native app packaging, embedded resource relocation and architecture verification.
- Release failure paths and cask generation exercised with synthetic mock artifacts:
  failed signing keeps the existing installation; rejected notarization creates no release.
- Native demo-window checks confirmed English menus/prompts, immediate invalid-JSON
  feedback, Cancel preserving edits for both Quit and window Close, and confirmed
  discard before Reload. The updated screenshot uses the actual views with example data.

## Follow-up verification

- Test execution on physical Intel hardware and the minimum supported macOS version.
- Configure the standalone DotShelf release workflow's Apple secrets for future releases.

Future features are tracked in the [roadmap](ROADMAP.md), and operational details
in the [release guide](RELEASING.md).
