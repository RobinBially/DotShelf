# DotShelf roadmap

Updated September 5, 2026. These are proposals, not promised release dates.

DotShelf is a fast, native workspace for recurring configuration files on a Mac.
Reliable edits, quick access and a useful change history are the product's focus.

## Available now

The first signed, notarized Universal app is available through GitHub Releases and
`brew install --cask robin-bially/tap/dotshelf`. The source stays on Robin Bially's
personal profile; the Homebrew tap lives in the same account.

## Next

| Feature | Why it matters |
|---|---|
| Conflict diff and merge | Compare external changes with unsaved edits without copying text elsewhere. Basic conflict detection is already implemented. |
| Backup history with restore and retention | Review changes, recover an earlier version and limit disk usage. |
| TOML, plain text and manual language selection | Support more dotfiles correctly instead of treating unknown files as shell. |
| Quick Open with ⌘P and file groups | Find files quickly as the sidebar grows. |
| JSON schema validation with line/column hints | Catch unsupported options and incorrect value types. |
| Project profiles and relative paths | Switch between projects without a long global list. |
| Comment-preserving JSONC formatting | Format without losing useful explanations. |

## Decisions

- Product name: **DotShelf**.
- English is the development and default UI language. Strings are stored in language resources.
- Distribution: a signed, notarized Universal macOS app and a Homebrew cask in the `robin-bially/tap` tap.
- Preserve the existing bundle ID during the rename so user preferences survive.
- The source repository is `robin-bially/DotShelf`.
  The tap `robin-bially/tap` in the same account hosts the cask.

The initial name search was not a trademark or domain clearance.
